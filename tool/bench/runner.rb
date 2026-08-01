# frozen_string_literal: true

require "json"
require "time"

require_relative "corpus"

module TypeProf
  module Bench
    # Measures one TypeProf commit against the corpus.
    #
    # Each commit is checked out into its own git worktree rather than checked
    # out in place. That keeps the repository's own working tree untouched (so
    # uncommitted work is fine), leaves HEAD alone if a run dies halfway, and
    # allows several commits to be measured concurrently.
    class Runner
      WORKTREE_DIR = File.join(ROOT, "tmp", "bench_wt")
      DATA_DIR = File.join(ROOT, "bench_data")

      # Recorded alongside the numbers because the flags affect them: enabling
      # `--show-errors` shifts the typed slot counts slightly.
      FLAGS = ["--show-stats", "--show-errors"].freeze

      def initialize(projects: Corpus.all, timeout: 600, jobs: 1)
        @projects = projects
        @timeout = timeout
        @jobs = jobs
      end

      def data_path(sha) = File.join(DATA_DIR, "#{sha}.json")

      # Data from an earlier run only counts if it covers every project we were
      # asked for. Otherwise a run narrowed with `--projects` would make later
      # full runs skip the commit and leave the gap in place.
      def measured?(sha)
        return false unless File.exist?(data_path(sha))

        measured = JSON.parse(File.read(data_path(sha)))["projects"].to_a.map { _1["name"] }
        (@projects.map(&:name) - measured).empty?
      rescue JSON::ParserError
        false
      end

      # Measures `sha` and writes bench_data/<sha>.json. Returns the data Hash.
      def run(sha)
        sha = resolve(sha)
        worktree = File.join(WORKTREE_DIR, sha)

        FileUtils.mkdir_p(WORKTREE_DIR)
        git!("worktree", "add", "-q", "--detach", worktree, sha)
        begin
          data = collect(sha, worktree)
        ensure
          git!("worktree", "remove", "--force", worktree)
        end

        FileUtils.mkdir_p(DATA_DIR)
        File.write(data_path(sha), JSON.pretty_generate(data))
        data
      end

      def install_gems(gemfile)
        Bundler.with_unbundled_env do
          system({ "BUNDLE_GEMFILE" => gemfile }, "bundle", "install", "--quiet",
                 out: File::NULL, err: File::NULL)
        end
      end

      private

      def collect(sha, worktree)
        gemfile = File.join(worktree, "Gemfile")
        data = metadata(sha, worktree)

        unless install_gems(gemfile)
          return data.merge(error: "bundle install failed", projects: [])
        end

        data.merge(projects: @projects.map { measure(_1, sha, worktree, gemfile) })
      end

      def measure(project, sha, worktree, gemfile)
        result = project.measure(
          bin: File.join(worktree, "bin/typeprof"),
          gemfile: gemfile,
          out_path: File.join(OUT_DIR, sha, "#{project.name}.out"),
          timeout: @timeout,
        )
        warn "    #{project.name}: #{result[:status]} #{result[:error]}" if result[:status] != :ok
        result
      end

      def metadata(sha, worktree)
        timestamp, date = git("log", "-1", "--format=%ct%n%cs", sha).lines.map(&:strip)
        {
          sha: sha,
          commit_timestamp: timestamp.to_i,
          commit_date: date,
          typeprof_version: typeprof_version(worktree),
          rbs_revision: rbs_revision(worktree),
          measured_at: Time.now.iso8601,
          jobs: @jobs,
          flags: FLAGS,
          host: { ruby: RUBY_VERSION, arch: RUBY_PLATFORM },
        }
      end

      def typeprof_version(worktree)
        File.read(File.join(worktree, "lib/typeprof/version.rb"))[/VERSION = "([^"]+)"/, 1]
      rescue SystemCallError
        nil
      end

      def rbs_revision(worktree)
        lock = File.read(File.join(worktree, "Gemfile.lock"))
        lock[%r{github\.com/ruby/rbs.*?\n\s*revision: (\h+)}m, 1]
      rescue SystemCallError
        nil
      end

      def resolve(rev) = git("rev-parse", rev).strip

      def git(*args) = IO.popen(["git", "-C", ROOT, *args], &:read)

      def git!(*args) = system("git", "-C", ROOT, *args, exception: true)
    end
  end
end
