# frozen_string_literal: true

require "bundler"
require "bundler/lockfile_parser"
require "fileutils"
require "timeout"

require_relative "metrics"

module TypeProf
  module Bench
    ROOT = File.expand_path("../..", __dir__)
    PROJECTS_DIR = File.join(ROOT, "tmp", "benchmark", "projects")
    OUT_DIR = File.join(ROOT, "tmp", "benchmark", "out")

    # Recorded alongside the numbers because the flags affect them: enabling
    # `--show-errors` shifts the typed slot counts slightly.
    FLAGS = ["--show-stats", "--show-errors"].freeze

    # Built once and handed to each child, rather than wrapping every spawn in
    # `Bundler.with_unbundled_env`, which swaps ENV in place around a block.
    UNBUNDLED_ENV = Bundler.unbundled_env.freeze

    module_function

    def bundle_env(gemfile) = UNBUNDLED_ENV.merge("BUNDLE_GEMFILE" => gemfile)

    def git(*args, dir: ROOT) = IO.popen(["git", "-C", dir, *args], &:read)

    def git!(*args, dir: ROOT) = system("git", "-C", dir, *args, exception: true)

    # The revision a lockfile pins ruby/rbs to, or nil if it does not use git.
    # The project and the measured commit have to agree on this.
    def rbs_revision(lock_path)
      sources = Bundler::LockfileParser.new(File.read(lock_path)).sources
      sources.grep(Bundler::Source::Git).find { _1.name == "rbs" }&.revision
    rescue SystemCallError
      nil
    end

    # `ref` is pinned so that only TypeProf changes between measurements. `setup`
    # runs once when the project is prepared, not on every measurement, because
    # backfilling replays the same projects over dozens of TypeProf commits.
    Project = Data.define(:name, :repo, :ref, :targets, :exclude, :setup) do
      def initialize(targets: ["."], exclude: [], setup: nil, **) = super

      def dir = File.join(PROJECTS_DIR, name)

      # Unified init + fetch + checkout for any ref (SHA / tag / branch).
      # `git clone --branch` is noisier (annotated tags emit a "is not a commit"
      # warning + detached HEAD advice) and doesn't accept SHAs. Fetching by SHA
      # works thanks to GitHub's uploadpack.allowAnySHA1InWant.
      def clone!
        return if Dir.exist?(File.join(dir, ".git"))

        FileUtils.mkdir_p(dir)
        Bench.git!("init", "-q", dir: dir)
        Bench.git!("remote", "add", "origin", repo, dir: dir)
        Bench.git!("fetch", "--depth", "1", "-q", "origin", ref, dir: dir)
        Bench.git!("checkout", "-q", "FETCH_HEAD", dir: dir)
      end

      # Clone and run the project's own setup. Setup steps are expected to be
      # idempotent so that re-running prepare on an existing checkout is cheap.
      def prepare!
        clone!
        return unless setup

        Dir.chdir(dir) do
          Bundler.with_unbundled_env { setup.call }
        end
      end

      # A project whose setup built an rbs collection has to be analysed inside
      # its own bundle: the collection lockfile refers to gems that ship their
      # own signatures, and those only resolve there. `prepare!` pins rbs to the
      # same revision, so TypeProf still runs against one rbs either way.
      def own_bundle? = File.exist?(File.join(dir, "rbs_collection.lock.yaml"))

      def measure(worktree:, out_path:, timeout:)
        gemfile = File.join(own_bundle? ? dir : worktree, "Gemfile")
        FileUtils.mkdir_p(File.dirname(out_path))
        argv = ["-o", out_path, *FLAGS, *exclude.flat_map { ["--exclude", _1] }, *targets]

        run = execute(File.join(worktree, "bin/typeprof"), gemfile, argv, out_path, timeout)
        base = { name: name, ref: ref }
        return base.merge(run) unless run[:status] == :ok

        begin
          metrics = Metrics.parse(File.read(out_path))
        rescue Metrics::ParseError => e
          return base.merge(run, status: :crash, error: "#{e.class}: #{e.message}")
        end

        # The dump is only an input to Metrics and runs to hundreds of KB per
        # project; a failed run keeps its own for diagnosis.
        FileUtils.rm_f([out_path, log_path_for(out_path)])
        base.merge(run, **metrics)
      end

      private

      def execute(bin, gemfile, argv, out_path, timeout)
        cmd = ["bundle", "exec", "ruby", bin, *argv]
        # The RBS dump goes to `-o out_path`, so both streams only carry
        # progress and error messages. Keep them together for diagnosis.
        log_path = log_path_for(out_path)
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        pid = Process.spawn(Bench.bundle_env(gemfile), *cmd, unsetenv_others: true,
                            chdir: dir, [:out, :err] => log_path)
        begin
          Timeout.timeout(timeout) { Process.waitpid(pid) }
        rescue Timeout::Error
          Process.kill("KILL", pid)
          Process.waitpid(pid)
          return { elapsed: elapsed_since(t), status: :timeout, error: "exceeded #{timeout}s" }
        end

        elapsed = elapsed_since(t)
        return { elapsed:, status: :ok, error: nil } if $?.success?

        { elapsed:, status: :crash, error: "exited with #{$?.exitstatus}: #{excerpt(log_path)}" }
      end

      def log_path_for(out_path) = "#{out_path}.log"

      def elapsed_since(t) = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t).round(2)

      # A Ruby exception puts its message on the first line; the frames at the
      # end are always the same three and say nothing.
      def excerpt(path)
        File.readlines(path).map(&:strip).reject(&:empty?).first(3).join(" / ")
      rescue SystemCallError
        ""
      end
    end

    module Projects
      module_function

      def add_gem(name, *args)
        return if File.read("Gemfile").match?(/^\s*gem ["']#{Regexp.escape(name)}["']/)

        system("bundle", "add", name, *args, exception: true)
      end

      # `rbs collection install` resolves gems from the project's own bundle, so
      # it has to run there rather than under TypeProf's. But the lockfile it
      # writes records the rbs version that produced it, and TypeProf fails to
      # load a collection built by a different version. Pin the project's rbs to
      # the revision TypeProf itself uses to satisfy both.
      def pin_rbs
        want = Bench.rbs_revision(File.join(ROOT, "Gemfile.lock")) or
          raise "cannot determine TypeProf's rbs revision"
        return if Bench.rbs_revision("Gemfile.lock") == want

        system("bundle", "add", "rbs", "--github", "ruby/rbs", "--ref", want, exception: true)
      end

      # Generates RBS for a Rails app.
      def setup_rails_rbs
        pin_rbs
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
          targets: ["app", "sig"],
          setup: -> { write_sqlite_config; setup_rails_rbs },
        ),
        # No setup: rubygems.org's Gemfile takes its Ruby requirement from
        # `.ruby-version` (4.0.6), which this repository does not run on, so
        # bundler refuses to install and rbs_rails cannot generate signatures.
        # Measuring without Rails RBS lowers the absolute numbers but still
        # tracks relative change across TypeProf commits, which is the point.
        Project.new(
          name: "rubygems.org",
          repo: "https://github.com/rubygems/rubygems.org.git",
          ref: "4e36c18deef651564e7029ad8c00594f7e207d1b", # 2026-07-30 master
          targets: ["app", "lib"],
        ),
      ].freeze

      def fetch(name)
        ALL.find { _1.name == name } or
          raise ArgumentError, "unknown project: #{name.inspect} (known: #{ALL.map(&:name).join(", ")})"
      end
    end
  end
end
