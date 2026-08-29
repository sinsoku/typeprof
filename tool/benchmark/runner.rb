require "json"
require_relative "projects"

module TypeProf
  module Benchmark
    # Prepares and measures every project, writes the two files
    # github-action-benchmark reads, and returns whether all analysed cleanly.
    def self.run
      # The first run clones the projects, which takes a minute or so.
      PROJECTS.each do |project|
        puts "Preparing #{ project.name }" unless Dir.exist?(project.dir)
        project.prepare!
      end

      # Almost always a no-op, but a stale lockfile (e.g. after switching
      # branches) would surface as a confusing per-project crash.
      system(bundle_env(File.join(ROOT, "Gemfile")), "bundle", "install", "--quiet",
             unsetenv_others: true, out: File::NULL, err: File::NULL) or
        raise "bundle install failed"

      analysis_time = []
      type_coverage = []
      failed = false

      PROJECTS.each do |project|
        result = project.measure
        if result[:status] == :ok
          typed, total = result[:overall].values_at(:typed, :total)
          pct = (typed * 100.0 / total).round(2)
          puts format("%-16s ok %8.2fs %8.2f%% %5d diagnostics",
                      result[:name], result[:elapsed], pct, result[:diagnostics])
          analysis_time << { name: result[:name], unit: "s", value: result[:elapsed] }
          type_coverage << { name: result[:name], unit: "%", value: pct }
        else
          failed = true
          puts format("%-16s %s: %s", result[:name], result[:status], result[:error])
        end
      end

      output_dir = File.join(ROOT, "tmp", "benchmark")
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "analysis_time.json"), JSON.pretty_generate(analysis_time))
      File.write(File.join(output_dir, "type_coverage.json"), JSON.pretty_generate(type_coverage))

      !failed
    end
  end
end
