# frozen_string_literal: true

require "json"
require "time"

require_relative "corpus"

module TypeProf
  module Bench
    # Measures one TypeProf commit against the corpus.
    #
    # The commit is checked out into a git worktree rather than checked out in
    # place, so the repository's own working tree stays untouched (uncommitted
    # work is fine) and HEAD is left alone even if a run dies halfway.
    class Runner
      WORKTREE_DIR = File.join(ROOT, "tmp", "bench_wt")
      DATA_DIR = File.join(ROOT, "bench_data")

      # A hang is one of the failures worth recording, so give each project a
      # generous ceiling: the slowest today is redmine at 13 seconds.
      TIMEOUT = 600

      def initialize(projects:)
        @projects = projects
      end

      def data_path(sha) = File.join(DATA_DIR, "#{sha}.json")

      # Data from an earlier run only counts if it covers every project we were
      # asked for. Otherwise a run narrowed with `--projects` would make later
      # full runs skip the commit and leave the gap in place.
      def measured?(sha)
        measured = JSON.parse(File.read(data_path(sha)))["projects"].to_a.map { _1["name"] }
        (@projects.map(&:name) - measured).empty?
      rescue Errno::ENOENT, JSON::ParserError
        false
      end

      # Measures `sha` and writes bench_data/<sha>.json. Returns the data Hash.
      # The commit's date comes from the caller, which already listed it.
      def run(sha, timestamp:, date:)
        worktree = File.join(WORKTREE_DIR, sha)

        add_worktree(sha, worktree)
        begin
          data = collect(sha, worktree, timestamp, date)
        ensure
          Bench.git!("worktree", "remove", "--force", worktree)
        end

        FileUtils.mkdir_p(DATA_DIR)
        File.write(data_path(sha), JSON.pretty_generate(data))
        data
      end

      private

      def add_worktree(sha, worktree)
        FileUtils.mkdir_p(WORKTREE_DIR)
        FileUtils.rm_rf(worktree)
        Bench.git!("worktree", "add", "-q", "--detach", worktree, sha)
      rescue RuntimeError
        # A run killed mid-flight leaves the worktree registered without its
        # directory, and `add` then refuses the path forever.
        Bench.git!("worktree", "prune")
        Bench.git!("worktree", "add", "-q", "--detach", worktree, sha)
      end

      def collect(sha, worktree, timestamp, date)
        data = metadata(sha, worktree, timestamp, date)

        unless install_gems(File.join(worktree, "Gemfile"))
          return data.merge(error: "bundle install failed", projects: [])
        end

        data.merge(projects: @projects.map { measure(_1, sha, worktree) })
      end

      def measure(project, sha, worktree)
        result = project.measure(
          worktree: worktree,
          out_path: File.join(OUT_DIR, sha, "#{project.name}.out"),
          timeout: TIMEOUT,
        )
        warn "    #{project.name}: #{result[:status]} #{result[:error]}" if result[:status] != :ok
        result
      end

      # Almost always a no-op: consecutive commits share a lockfile, so bundler
      # finds everything already present.
      def install_gems(gemfile)
        system(Bench.bundle_env(gemfile), "bundle", "install", "--quiet",
               unsetenv_others: true, out: File::NULL, err: File::NULL)
      end

      def metadata(sha, worktree, timestamp, date)
        {
          sha: sha,
          commit_timestamp: timestamp,
          commit_date: date,
          typeprof_version: typeprof_version(worktree),
          rbs_revision: Bench.rbs_revision(File.join(worktree, "Gemfile.lock")),
          measured_at: Time.now.iso8601,
          flags: FLAGS,
          host: { ruby: RUBY_VERSION, arch: RUBY_PLATFORM },
        }
      end

      def typeprof_version(worktree)
        File.read(File.join(worktree, "lib/typeprof/version.rb"))[/VERSION = "([^"]+)"/, 1]
      rescue SystemCallError
        nil
      end
    end
  end
end
