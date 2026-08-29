require "fileutils"
require "timeout"
require_relative "metrics"

module TypeProf
  module Benchmark
    ROOT = File.expand_path("../..", __dir__)
    TMP_DIR = File.join(ROOT, "tmp", "benchmark")
    PROJECTS_DIR = File.join(TMP_DIR, "projects")
    OUT_DIR = File.join(TMP_DIR, "out")

    # `--no-collection` pins the bare analysis even if an rbs_collection.yaml appears in cwd.
    FLAGS = ["--no-collection", "--show-stats", "--show-errors"].freeze

    # ~8x the slowest project today; even two hangs in a row fit in CI's 15-minute job.
    TIMEOUT = 300

    # `ref` is pinned so that only TypeProf changes between measurements.
    class Project
      attr_reader :name

      def initialize(name:, repo:, ref:, exclude: [])
        @name = name
        @repo = repo
        @ref = ref
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
        # A half-made clone would pass the guard above forever; let the next run retry.
        FileUtils.rm_rf(dir)
        raise
      end

      def measure
        FileUtils.mkdir_p(OUT_DIR)
        out_path = File.join(OUT_DIR, "#{ @name }.out")
        cmd = ["bundle", "exec", "ruby", File.join(ROOT, "bin/typeprof"),
               "-o", out_path, *FLAGS,
               *@exclude.flat_map {|glob| ["--exclude", File.expand_path(glob, dir)] },
               dir]

        result = { name: @name }.merge(execute(cmd))
        result.merge!(Metrics.parse(File.read(out_path))) if result[:status] == :ok
        result
      end

      private

      def git!(*args) = system("git", "-C", dir, *args, exception: true)

      def execute(cmd)
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        pid = Process.spawn(*cmd)
        begin
          Timeout.timeout(TIMEOUT) { Process.waitpid(pid) }
        rescue Timeout::Error
          Process.kill("KILL", pid)
          Process.waitpid(pid)
          return { status: :timeout, error: "exceeded #{ TIMEOUT }s" }
        end

        if $?.success?
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t).round(2)
          { status: :ok, elapsed: }
        else
          { status: :crash, error: "exited with #{ $?.exitstatus || "signal #{ $?.termsig }" }" }
        end
      end
    end

    # `exclude` lists the files the project cannot parse on purpose (broken
    # test fixtures and ERB templates), so "failed to analyze" always means
    # a TypeProf regression.
    PROJECTS = [
      Project.new(
        name: "typeprof",
        repo: "https://github.com/ruby/typeprof.git",
        ref: "v0.32.0",
        exclude: [
          "scenario/**/*",
          "test/fixtures/exclude_test/templates/page.rb",
          "test/fixtures/syntax_error/syntax_error.rb",
          "test/fixtures/syntax_error/syntax_error.rbs",
        ],
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
        exclude: ["lib/generators/redmine_plugin_model/templates/migration.rb"],
      ),
      Project.new(
        name: "rubygems.org",
        repo: "https://github.com/rubygems/rubygems.org.git",
        ref: "2abc82667d02ef7ae3a1433d621c1f7463985c6d", # 2026-08-28 master
      ),
    ].freeze
  end
end
