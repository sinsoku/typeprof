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

        result = { name: @name }.merge(execute(argv))
        return result unless result[:status] == :ok

        result.merge(Metrics.parse(File.read(out_path)))
      end

      private

      def git!(*args) = system("git", "-C", dir, *args, exception: true)

      def execute(argv)
        cmd = ["bundle", "exec", "ruby", File.join(ROOT, "bin/typeprof"), *argv]
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        pid = Process.spawn(*cmd)
        begin
          Timeout.timeout(TIMEOUT) { Process.waitpid(pid) }
        rescue Timeout::Error
          Process.kill("KILL", pid)
          Process.waitpid(pid)
          return { status: :timeout, error: "exceeded #{ TIMEOUT }s" }
        end

        unless $?.success?
          return { status: :crash, error: "exited with #{ $?.exitstatus || "signal #{ $?.termsig }" }" }
        end

        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t).round(2)
        { elapsed:, status: :ok }
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
