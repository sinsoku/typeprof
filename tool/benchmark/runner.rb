# frozen_string_literal: true

require "time"

require_relative "../../lib/typeprof/version"
require_relative "projects"

module TypeProf
  module Benchmark
    # Measures the working tree — uncommitted changes included — against the
    # benchmark projects.
    class Runner
      # A hang is one of the failures worth recording, so the ceiling is only
      # there to stop one; the slowest project today takes a few seconds.
      TIMEOUT = 600

      def run_working_tree
        install_gems!(File.join(ROOT, "Gemfile"))
        results = PROJECTS.map { measure(_1) }
        sha = Benchmark.git("rev-parse", "HEAD").strip
        dirty = !Benchmark.git("status", "--porcelain").empty?
        { sha: sha, dirty: dirty }.merge(provenance, projects: results)
      end

      private

      def measure(project)
        result = project.measure(
          worktree: ROOT,
          out_path: File.join(OUT_DIR, "#{project.name}.out"),
          timeout: TIMEOUT,
        )
        warn "    #{project.name}: #{result[:status]} #{result[:error]}" if result[:status] != :ok
        result
      end

      # Almost always a no-op, but a lockfile change (e.g. after switching
      # branches) would otherwise surface as a confusing per-project crash.
      def install_gems!(gemfile)
        system(Benchmark.bundle_env(gemfile), "bundle", "install", "--quiet",
               unsetenv_others: true, out: File::NULL, err: File::NULL) or
          raise "bundle install failed for #{gemfile}"
      end

      def provenance
        {
          typeprof_version: TypeProf::VERSION,
          rbs_revision: Benchmark.rbs_revision(File.join(ROOT, "Gemfile.lock")),
          measured_at: Time.now.iso8601,
          flags: FLAGS,
          host: { ruby: RUBY_VERSION, arch: RUBY_PLATFORM },
        }
      end
    end
  end
end
