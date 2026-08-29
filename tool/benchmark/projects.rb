require "fileutils"
require "timeout"
require_relative "metrics"

module TypeProf
  module Benchmark
    ROOT = File.expand_path("../..", __dir__)
    PROJECTS_DIR = File.join(ROOT, "tmp", "benchmark", "projects")
    OUT_DIR = File.join(ROOT, "tmp", "benchmark", "out")

    # `--no-collection` pins the bare analysis even if an rbs_collection.yaml ever
    # appears in cwd; `--show-errors` also shifts the typed counts. The data series
    # published on gh-pages was measured with exactly these flags.
    FLAGS = ["--no-collection", "--show-stats", "--show-errors"].freeze

    # ~30x the slowest project today; even four hangs in a row fit in CI's 15-minute job.
    TIMEOUT = 120

    # `ref` is pinned so that only TypeProf changes between measurements; a project is
    # analysed exactly as cloned, so its checkout is fully determined by the ref.
    class Project
      attr_reader :name

      def initialize(name:, repo:, ref:, targets: ["."], exclude: [])
        @name = name
        @repo = repo
        @ref = ref
        @targets = targets
        @exclude = exclude
      end

      def dir = File.join(PROJECTS_DIR, @name)

      # `git clone --branch` warns on annotated tags and rejects SHAs; init + fetch
      # handles any ref (GitHub allows fetching arbitrary SHAs).
      def prepare!
        return if Dir.exist?(dir)

        puts "Preparing #{ @name }"
        FileUtils.mkdir_p(dir)
        git!("init", "-q")
        git!("remote", "add", "origin", @repo)
        git!("fetch", "--depth", "1", "-q", "origin", @ref)
        git!("checkout", "-q", "FETCH_HEAD")
      rescue Exception
        # A half-made clone would pass the guard above forever; retry it instead.
        FileUtils.rm_rf(dir)
        raise
      end

      def measure
        FileUtils.mkdir_p(OUT_DIR)
        out_path = File.join(OUT_DIR, "#{ @name }.out")
        argv = ["-o", out_path, *FLAGS,
                *@exclude.flat_map {|glob| ["--exclude", File.expand_path(glob, dir)] },
                *@targets.map {|target| File.expand_path(target, dir) }]

        result = { name: @name }.merge(execute(argv, out_path))
        return result unless result[:status] == :ok

        metrics = Metrics.parse(File.read(out_path))
        # The dump is only Metrics' input and runs to hundreds of KB; failures keep theirs for diagnosis.
        FileUtils.rm_f([out_path, log_path_for(out_path)])
        result.merge(metrics)
      end

      private

      def git!(*args) = system("git", "-C", dir, *args, exception: true)

      def execute(argv, out_path)
        cmd = ["bundle", "exec", "ruby", File.join(ROOT, "bin/typeprof"), *argv]
        # The dump goes to `-o`, so both streams carry only progress and errors; keep them in one log.
        log_path = log_path_for(out_path)
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        pid = Process.spawn(*cmd, [:out, :err] => log_path)
        begin
          Timeout.timeout(TIMEOUT) { Process.waitpid(pid) }
        rescue Timeout::Error
          Process.kill("KILL", pid)
          Process.waitpid(pid)
          return { elapsed: elapsed_since(t), status: :timeout, error: "exceeded #{ TIMEOUT }s" }
        end

        elapsed = elapsed_since(t)
        return { elapsed:, status: :ok } if $?.success?

        status = $?.exitstatus || "signal #{ $?.termsig }"
        { elapsed:, status: :crash, error: "exited with #{ status }: #{ excerpt(log_path) }" }
      end

      def log_path_for(out_path) = "#{ out_path }.log"

      def elapsed_since(t) = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t).round(2)

      # Keep only the first three lines: the exception message leads, and the rest is backtrace.
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
