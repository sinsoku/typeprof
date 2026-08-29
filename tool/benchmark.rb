#!/usr/bin/env ruby

# Measures TypeProf against the benchmark projects.
#
# Analyses the working tree as it is — uncommitted changes included — writes
# the two files github-action-benchmark reads, prints a per-project summary,
# and fails if any project does not analyse cleanly.
#
#   $ ruby tool/benchmark.rb
#   typeprof         ok    1.79s   78.37%   475 diagnostics
#   ...
#   => tmp/benchmark/speed.json     (customSmallerIsBetter, seconds)
#   => tmp/benchmark/coverage.json  (customBiggerIsBetter, typed slots %)

require "json"
require_relative "benchmark/projects"

module TypeProf
  module Benchmark
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

    speed = []
    coverage = []
    failed = false

    PROJECTS.each do |project|
      result = project.measure
      if result[:status] == :ok
        typed, total = result[:overall].values_at(:typed, :total)
        pct = (typed * 100.0 / total).round(2)
        puts format("%-16s ok %8.2fs %8.2f%% %5d diagnostics",
                    result[:name], result[:elapsed], pct, result[:diagnostics])
        speed << { name: result[:name], unit: "s", value: result[:elapsed] }
        coverage << { name: result[:name], unit: "%", value: pct }
      else
        failed = true
        puts format("%-16s %s: %s", result[:name], result[:status], result[:error])
      end
    end

    gha_dir = File.join(ROOT, "tmp", "benchmark")
    FileUtils.mkdir_p(gha_dir)
    File.write(File.join(gha_dir, "speed.json"), JSON.pretty_generate(speed))
    File.write(File.join(gha_dir, "coverage.json"), JSON.pretty_generate(coverage))

    exit 1 if failed
  end
end
