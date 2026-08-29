#!/usr/bin/env ruby

# Measures TypeProf against the benchmark projects.
#
# Analyses the working tree as it is — uncommitted changes included — writes
# the two files github-action-benchmark reads, prints a per-project summary,
# and fails if any project does not analyse cleanly.
#
#   $ ruby tool/benchmark.rb
#   typeprof         ok          1.96s    79.04%  1002 diagnostics
#   ...
#   => tmp/benchmark/analysis_time.json  (customSmallerIsBetter, seconds)
#   => tmp/benchmark/type_coverage.json  (customBiggerIsBetter, typed slots %)

require "fileutils"
require "json"
require_relative "benchmark/projects"

module TypeProf
  module Benchmark
    def self.run
      # `bundle exec` for the children resolves the Gemfile from here.
      Dir.chdir(ROOT)

      # The first run clones the projects, which takes a minute or so.
      PROJECTS.each(&:prepare!)

      # Almost always a no-op, but a stale lockfile (e.g. after switching
      # branches) would surface as a confusing per-project crash.
      system("bundle", "install", "--quiet") or raise "bundle install failed"

      analysis_time = []
      type_coverage = []
      failed = false

      PROJECTS.each do |project|
        result = project.measure
        if result[:status] == :ok
          typed, total = result[:overall].values_at(:typed, :total)
          pct = total.zero? ? 0.0 : (typed * 100.0 / total).round(2)
          puts format("%-16s %-7s %8.2fs %8.2f%% %5d diagnostics",
                      result[:name], result[:status], result[:elapsed], pct, result[:diagnostics])
          analysis_time << { name: result[:name], unit: "s", value: result[:elapsed] }
          type_coverage << { name: result[:name], unit: "%", value: pct }
        else
          failed = true
          puts format("%-16s %-7s %s", result[:name], result[:status], result[:error])
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

exit 1 unless TypeProf::Benchmark.run
