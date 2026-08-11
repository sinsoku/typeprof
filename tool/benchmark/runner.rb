# frozen_string_literal: true

require "json"
require "time"

require_relative "projects"

module TypeProf
  module Bench
    # Measures a TypeProf checkout against the benchmark projects: a committed
    # sha into the archive, or the working tree as it stands.
    #
    # A commit is checked out into a git worktree rather than checked out in
    # place, so the repository's own working tree stays untouched (uncommitted
    # work is fine) and HEAD is left alone even if a run dies halfway.
    class Runner
      WORKTREE_DIR = File.join(ROOT, "tmp", "benchmark", "wt")
      DATA_DIR = File.join(ROOT, "benchmark_data")

      # A hang is one of the failures worth recording, so the ceiling is only
      # there to stop one; the slowest project today takes 13 seconds.
      TIMEOUT = 600

      def data_path(sha, name) = File.join(DATA_DIR, sha, "#{name}.json")

      def measured?(sha) = Projects::ALL.all? { File.exist?(data_path(sha, _1.name)) }

      # Measures the projects that have no file yet and returns their results,
      # so adding a project later fills only the gap. Each file is
      # self-contained: the metadata is repeated per project because separate
      # backfills may measure the same commit under different conditions.
      # The commit's date comes from the caller, which already listed it.
      def run(sha, timestamp:, date:, force: false)
        worktree = File.join(WORKTREE_DIR, sha)

        add_worktree(sha, worktree)
        begin
          install_gems!(File.join(worktree, "Gemfile"))
          meta = metadata(sha, worktree, timestamp, date)

          Projects::ALL.filter_map do |project|
            path = data_path(sha, project.name)
            next if !force && File.exist?(path)

            result = measure(project, sha, worktree)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, JSON.pretty_generate(meta.merge(result)))
            result
          end
        ensure
          Bench.git!("worktree", "remove", "--force", worktree)
        end
      end

      # Measures the working tree as it is, uncommitted changes included. The
      # result goes to the caller, not the archive: a dirty tree's numbers
      # correspond to no commit.
      def run_working_tree
        install_gems!(File.join(ROOT, "Gemfile"))
        results = Projects::ALL.map { measure(_1, "working-tree", ROOT) }
        sha = Bench.git("rev-parse", "HEAD").strip
        dirty = !Bench.git("status", "--porcelain").empty?
        { sha: sha, dirty: dirty }.merge(provenance(ROOT), projects: results)
      end

      private

      # A run killed mid-flight leaves the worktree registered without its
      # directory, and `add` then refuses the path forever.
      def add_worktree(sha, worktree)
        FileUtils.rm_rf(worktree)
        Bench.git!("worktree", "prune")
        Bench.git!("worktree", "add", "-q", "--detach", worktree, sha)
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
      def install_gems!(gemfile)
        system(Bench.bundle_env(gemfile), "bundle", "install", "--quiet",
               unsetenv_others: true, out: File::NULL, err: File::NULL) or
          raise "bundle install failed for #{gemfile}"
      end

      def metadata(sha, worktree, timestamp, date)
        { sha: sha, commit_timestamp: timestamp, commit_date: date }.merge(provenance(worktree))
      end

      # The conditions the measurement ran under, recorded with every result.
      def provenance(worktree)
        {
          typeprof_version: typeprof_version(worktree),
          rbs_revision: Bench.rbs_revision(File.join(worktree, "Gemfile.lock")),
          measured_at: Time.now.iso8601,
          flags: FLAGS,
          host: { ruby: RUBY_VERSION, arch: RUBY_PLATFORM },
        }
      end

      def typeprof_version(worktree)
        File.read(File.join(worktree, "lib/typeprof/version.rb"))[/VERSION = "([^"]+)"/, 1]
      end
    end
  end
end
