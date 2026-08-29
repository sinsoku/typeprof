# frozen_string_literal: true

require "bundler"
require "fileutils"
require "timeout"

require_relative "metrics"

module TypeProf
  module Benchmark
    ROOT = File.expand_path("../..", __dir__)
    PROJECTS_DIR = File.join(ROOT, "tmp", "benchmark", "projects")
    OUT_DIR = File.join(ROOT, "tmp", "benchmark", "out")

    # `--show-errors` feeds the diagnostics tally, and also shifts the typed
    # counts slightly — the published history was measured with it, so it
    # stays for comparability.
    FLAGS = ["--show-stats", "--show-errors"].freeze

    # A hang is one of the failures worth catching; 120s is ~30x the slowest
    # project today and keeps even four simultaneous hangs inside CI's
    # 15-minute job timeout.
    TIMEOUT = 120

    # Built once and handed to each child, rather than wrapping every spawn in
    # `Bundler.with_unbundled_env`, which swaps ENV in place around a block.
    UNBUNDLED_ENV = Bundler.unbundled_env.freeze

    module_function

    def bundle_env(gemfile) = UNBUNDLED_ENV.merge("BUNDLE_GEMFILE" => gemfile)

    def git!(*args, dir:) = system("git", "-C", dir, *args, exception: true)

    # `ref` is pinned so that only TypeProf changes between measurements. A
    # project is analysed exactly as cloned — no gem installation, no RBS
    # generation — so the checkout is fully determined by its ref.
    Project = Data.define(:name, :repo, :ref, :targets, :exclude) do
      def initialize(targets: ["."], exclude: [], **) = super

      def dir = File.join(PROJECTS_DIR, name)

      # Unified init + fetch + checkout for any ref (SHA / tag / branch).
      # `git clone --branch` is noisier (annotated tags emit a "is not a commit"
      # warning + detached HEAD advice) and doesn't accept SHAs. Fetching by SHA
      # works thanks to GitHub's uploadpack.allowAnySHA1InWant.
      def prepare!
        return if Dir.exist?(File.join(dir, ".git"))

        FileUtils.mkdir_p(dir)
        Benchmark.git!("init", "-q", dir: dir)
        Benchmark.git!("remote", "add", "origin", repo, dir: dir)
        Benchmark.git!("fetch", "--depth", "1", "-q", "origin", ref, dir: dir)
        Benchmark.git!("checkout", "-q", "FETCH_HEAD", dir: dir)
      end

      def measure
        FileUtils.mkdir_p(OUT_DIR)
        out_path = File.join(OUT_DIR, "#{name}.out")
        argv = ["-o", out_path, *FLAGS, *exclude.flat_map { ["--exclude", _1] }, *targets]

        run = { name: name }.merge(execute(argv, out_path))
        return run unless run[:status] == :ok

        begin
          metrics = Metrics.parse(File.read(out_path))
        rescue Metrics::ParseError => e
          return run.merge(status: :crash, error: "#{e.class}: #{e.message}")
        end

        # The dump is only an input to Metrics and runs to hundreds of KB per
        # project; a failed run keeps its own for diagnosis.
        FileUtils.rm_f([out_path, log_path_for(out_path)])
        run.merge(metrics)
      end

      private

      def execute(argv, out_path)
        cmd = ["bundle", "exec", "ruby", File.join(ROOT, "bin/typeprof"), *argv]
        # The RBS dump goes to `-o out_path`, so both streams only carry
        # progress and error messages. Keep them together for diagnosis.
        log_path = log_path_for(out_path)
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        pid = Process.spawn(Benchmark.bundle_env(File.join(ROOT, "Gemfile")), *cmd,
                            unsetenv_others: true, chdir: dir, [:out, :err] => log_path)
        begin
          Timeout.timeout(TIMEOUT) { Process.waitpid(pid) }
        rescue Timeout::Error
          Process.kill("KILL", pid)
          Process.waitpid(pid)
          return { elapsed: elapsed_since(t), status: :timeout, error: "exceeded #{TIMEOUT}s" }
        end

        elapsed = elapsed_since(t)
        return { elapsed:, status: :ok } if $?.success?

        { elapsed:, status: :crash, error: "exited with #{$?.exitstatus}: #{excerpt(log_path)}" }
      end

      def log_path_for(out_path) = "#{out_path}.log"

      def elapsed_since(t) = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t).round(2)

      # A Ruby exception puts its message on the first line; the frames at the
      # end are always the same three and say nothing.
      def excerpt(path)
        File.readlines(path).map(&:strip).reject(&:empty?).first(3).join(" / ")
      end
    end

    PROJECTS = [
      Project.new(
        name: "typeprof",
        repo: "https://github.com/ruby/typeprof.git",
        ref: "v0.31.1",
        exclude: ["scenario/**/*"],
      ),
      Project.new(
        name: "optcarrot",
        repo: "https://github.com/mame/optcarrot.git",
        ref: "9c88f5f752341087270b0e86e741d73f19e52369", # 2026-04-29 HEAD
      ),
      Project.new(
        name: "redmine",
        repo: "https://github.com/redmine/redmine.git",
        ref: "6.1.1",
        targets: ["app"],
      ),
      Project.new(
        name: "rubygems.org",
        repo: "https://github.com/rubygems/rubygems.org.git",
        ref: "4e36c18deef651564e7029ad8c00594f7e207d1b", # 2026-07-30 master
        targets: ["app", "lib"],
      ),
    ].freeze
  end
end
