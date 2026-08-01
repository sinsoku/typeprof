# frozen_string_literal: true

require "bundler"
require "fileutils"
require "timeout"

require_relative "metrics"

module TypeProf
  module Bench
    ROOT = File.expand_path("../..", __dir__)
    CORPUS_DIR = File.join(ROOT, "tmp", "bench_corpus")
    OUT_DIR = File.join(ROOT, "tmp", "bench_out")

    # A project to run TypeProf against.
    #
    # `ref` is pinned so that only TypeProf changes between measurements. `setup`
    # runs once when the project is prepared, not on every measurement, because
    # backfilling replays the same corpus over dozens of TypeProf commits.
    Project = Data.define(:name, :repo, :ref, :targets, :exclude, :setup) do
      def dir = File.join(CORPUS_DIR, name)

      def cloned? = Dir.exist?(File.join(dir, ".git"))

      # Unified init + fetch + checkout for any ref (SHA / tag / branch).
      # `git clone --branch` is noisier (annotated tags emit a "is not a commit"
      # warning + detached HEAD advice) and doesn't accept SHAs. Fetching by SHA
      # works thanks to GitHub's uploadpack.allowAnySHA1InWant.
      def clone!
        return if cloned?

        FileUtils.mkdir_p(CORPUS_DIR)
        run!("git init -q #{dir}")
        run!("git -C #{dir} remote add origin #{repo}")
        run!("git -C #{dir} fetch --depth 1 -q origin #{ref}")
        run!("git -C #{dir} checkout -q FETCH_HEAD")
      end

      # Clone and run the project's own setup. Setup steps are expected to be
      # idempotent so that re-running prepare on an existing corpus is cheap.
      def prepare!
        clone!
        return unless setup

        Dir.chdir(dir) do
          Bundler.with_unbundled_env { setup.call }
        end
      end

      # Run one TypeProf binary against this project and return raw metrics.
      #
      # `bin` and `gemfile` come from a git worktree of the TypeProf commit being
      # measured. Pointing BUNDLE_GEMFILE at that worktree pins rbs to TypeProf's
      # own lockfile instead of whatever the target project happens to bundle.
      def measure(bin:, gemfile:, out_path: File.join(OUT_DIR, "#{name}.out"), timeout: 600)
        FileUtils.mkdir_p(File.dirname(out_path))
        argv = ["-o", out_path, "--show-stats", "--show-errors",
                *exclude.flat_map { ["--exclude", _1] }, *targets]
        base = { name: name, ref: ref }

        elapsed, status, error = execute(bin, gemfile, argv, out_path, timeout)
        return base.merge(status: status, elapsed: elapsed, error: error) if status != :ok

        begin
          base.merge(status: :ok, elapsed: elapsed, **Metrics.parse(File.read(out_path)))
        rescue Metrics::ParseError => e
          base.merge(status: :crash, elapsed: elapsed, error: "#{e.class}: #{e.message}")
        end
      end

      private

      def execute(bin, gemfile, argv, out_path, timeout)
        cmd = ["bundle", "exec", "ruby", bin, *argv]
        # The RBS dump goes to `-o out_path`, so both streams only carry
        # progress and error messages. Keep them together for diagnosis.
        log_path = "#{out_path}.log"
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Bundler.with_unbundled_env do
          pid = Process.spawn({ "BUNDLE_GEMFILE" => gemfile }, *cmd,
                              chdir: dir, [:out, :err] => log_path)
          begin
            Timeout.timeout(timeout) { Process.waitpid(pid) }
          rescue Timeout::Error
            Process.kill("KILL", pid)
            Process.waitpid(pid)
            return [elapsed_since(t), :timeout, "exceeded #{timeout}s"]
          end
        end

        elapsed = elapsed_since(t)
        return [elapsed, :ok, nil] if $?.success?

        [elapsed, :crash, "exited with #{$?.exitstatus}: #{tail(log_path)}"]
      end

      def elapsed_since(t) = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t).round(2)

      def tail(path, lines = 5)
        File.readlines(path).last(lines).join.strip
      rescue SystemCallError
        ""
      end

      def run!(cmd) = system(cmd, out: $stderr, exception: true)
    end

    module Corpus
      module_function

      def project(name:, repo:, ref:, targets: ["."], exclude: [], setup: nil)
        Project.new(name:, repo:, ref:, targets:, exclude:, setup:)
      end

      # Adds a gem to the target project's Gemfile unless it is already there.
      def add_gem(name, *args)
        return if File.read("Gemfile").include?(name)

        system("bundle", "add", name, *args, exception: true)
      end

      # Generates RBS for a Rails app. Each step is guarded for idempotency so
      # that re-preparing an existing corpus skips the work already done.
      def setup_rails_rbs
        add_gem("rbs_rails", "-v", "0.13.1")
        system("bin/rails", "db:migrate", exception: true) unless File.exist?("db/schema.rb")
        system("bundle exec rbs collection init", exception: true) unless File.exist?("rbs_collection.yaml")
        system("bundle exec rbs collection install", exception: true) unless File.exist?("rbs_collection.lock.yaml")
        system("bundle exec rbs_rails all", exception: true) unless Dir.exist?("sig/rbs_rails")
      end

      def write_sqlite_config
        return if File.exist?("config/database.yml")

        File.write("config/database.yml", <<~YAML)
          development:
            adapter: sqlite3
            database: db/development.sqlite3
        YAML
      end

      ALL = [
        project(
          name: "typeprof",
          repo: "https://github.com/ruby/typeprof.git",
          ref: "v0.31.1",
          exclude: ["scenario/**/*"],
        ),
        project(
          name: "optcarrot",
          repo: "https://github.com/mame/optcarrot.git",
          ref: "9c88f5f752341087270b0e86e741d73f19e52369", # 2026-04-29 HEAD
        ),
        project(
          name: "redmine",
          repo: "https://github.com/redmine/redmine.git",
          ref: "6.1.1",
          targets: ["app", "sig"],
          setup: -> { write_sqlite_config; setup_rails_rbs },
        ),
        # No setup: rubygems.org's Gemfile takes its Ruby requirement from
        # `.ruby-version` (4.0.6), which this repository does not run on, so
        # bundler refuses to install and rbs_rails cannot generate signatures.
        # Measuring without Rails RBS lowers the absolute numbers but still
        # tracks relative change across TypeProf commits, which is the point.
        project(
          name: "rubygems.org",
          repo: "https://github.com/rubygems/rubygems.org.git",
          ref: "4e36c18deef651564e7029ad8c00594f7e207d1b", # 2026-07-30 master
          targets: ["app", "lib"],
        ),
      ].freeze

      def all = ALL

      def fetch(name)
        ALL.find { _1.name == name } or
          raise ArgumentError, "unknown project: #{name.inspect} (known: #{ALL.map(&:name).join(", ")})"
      end
    end
  end
end
