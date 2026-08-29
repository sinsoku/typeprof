require "bundler"
require "fileutils"
require "timeout"
require_relative "metrics"

module TypeProf
  module Benchmark
    ROOT = File.expand_path("../..", __dir__)
    PROJECTS_DIR = File.join(ROOT, "tmp", "benchmark", "projects")
    OUT_DIR = File.join(ROOT, "tmp", "benchmark", "out")

    # `--show-errors` also shifts the typed counts; the published history was measured with it.
    FLAGS = ["--show-stats", "--show-errors"].freeze

    # ~30x the slowest project today; even four simultaneous hangs fit in CI's 15-minute job.
    TIMEOUT = 120

    # `Bundler.with_unbundled_env` swaps ENV in place, so build the environment once instead.
    UNBUNDLED_ENV = Bundler.unbundled_env.freeze

    module_function

    def bundle_env(gemfile) = UNBUNDLED_ENV.merge("BUNDLE_GEMFILE" => gemfile)

    def git!(*args, dir:) = system("git", "-C", dir, *args, exception: true)

    # `ref` is pinned so that only TypeProf changes between measurements; a project is
    # analysed exactly as cloned, so its checkout is fully determined by the ref.
    Project = Data.define(:name, :repo, :ref, :targets, :exclude) do
      def initialize(targets: ["."], exclude: [], **) = super

      def dir = File.join(PROJECTS_DIR, name)

      # `git clone --branch` warns on annotated tags and rejects SHAs; init + fetch
      # handles any ref (GitHub allows fetching arbitrary SHAs).
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
        out_path = File.join(OUT_DIR, "#{ name }.out")
        argv = ["-o", out_path, *FLAGS, *exclude.flat_map {|pat| ["--exclude", pat] }, *targets]

        run = { name: name }.merge(execute(argv, out_path))
        return run unless run[:status] == :ok

        begin
          metrics = Metrics.parse(File.read(out_path))
        rescue Metrics::ParseError => e
          return run.merge(status: :crash, error: "#{ e.class }: #{ e.message }")
        end

        # The dump is only Metrics' input and runs to hundreds of KB; failures keep theirs for diagnosis.
        FileUtils.rm_f([out_path, log_path_for(out_path)])
        run.merge(metrics)
      end

      private

      def execute(argv, out_path)
        cmd = ["bundle", "exec", "ruby", File.join(ROOT, "bin/typeprof"), *argv]
        # The dump goes to `-o`, so both streams carry only progress and errors; keep them in one log.
        log_path = log_path_for(out_path)
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        pid = Process.spawn(Benchmark.bundle_env(File.join(ROOT, "Gemfile")), *cmd,
                            unsetenv_others: true, chdir: dir, [:out, :err] => log_path)
        begin
          Timeout.timeout(TIMEOUT) { Process.waitpid(pid) }
        rescue Timeout::Error
          Process.kill("KILL", pid)
          Process.waitpid(pid)
          return { elapsed: elapsed_since(t), status: :timeout, error: "exceeded #{ TIMEOUT }s" }
        end

        elapsed = elapsed_since(t)
        return { elapsed:, status: :ok } if $?.success?

        { elapsed:, status: :crash, error: "exited with #{ $?.exitstatus }: #{ excerpt(log_path) }" }
      end

      def log_path_for(out_path) = "#{ out_path }.log"

      def elapsed_since(t) = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t).round(2)

      # The exception message is on the first line; the trailing frames are always the same three.
      def excerpt(path)
        File.readlines(path).map(&:strip).reject(&:empty?).first(3).join(" / ")
      end
    end

    PROJECTS = [
      Project.new(
        name: "typeprof",
        repo: "https://github.com/ruby/typeprof.git",
        ref: "v0.32.0",
        exclude: ["scenario/**/*"],
      ),
      Project.new(
        name: "optcarrot",
        repo: "https://github.com/mame/optcarrot.git",
        ref: "c215378a27b2dce8d8e5d98a3ed75e0354c5a840", # 2026-05-10 master
      ),
      Project.new(
        name: "redmine",
        repo: "https://github.com/redmine/redmine.git",
        ref: "7.0.1",
        targets: ["app"],
      ),
      Project.new(
        name: "rubygems.org",
        repo: "https://github.com/rubygems/rubygems.org.git",
        ref: "2abc82667d02ef7ae3a1433d621c1f7463985c6d", # 2026-08-28 master
        targets: ["app", "lib"],
      ),
    ].freeze
  end
end
