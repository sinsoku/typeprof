#!/usr/bin/env ruby
# frozen_string_literal: true

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
    # A hang is one of the failures worth catching, so the ceiling is only
    # there to stop one; the slowest project today takes a few seconds.
    TIMEOUT = 600

    # The first run clones the projects, which takes a minute or so; after
    # that this is one directory check per project.
    PROJECTS.each do |project|
      puts "Preparing #{project.name}" unless Dir.exist?(project.dir)
      project.prepare!
    end

    # Almost always a no-op, but a lockfile change (e.g. after switching
    # branches) would otherwise surface as a confusing per-project crash.
    system(bundle_env(File.join(ROOT, "Gemfile")), "bundle", "install", "--quiet",
           unsetenv_others: true, out: File::NULL, err: File::NULL) or
      raise "bundle install failed"

    results = PROJECTS.map do |project|
      result = project.measure(worktree: ROOT,
                               out_path: File.join(OUT_DIR, "#{project.name}.out"),
                               timeout: TIMEOUT)
      if result[:status] == :ok
        typed, total = result[:overall].values_at(:typed, :total)
        puts format("%-16s ok %8.2fs %8.2f%% %5d diagnostics",
                    result[:name], result[:elapsed], typed * 100.0 / total, result[:diagnostics])
      else
        puts format("%-16s %s: %s", result[:name], result[:status], result[:error])
      end
      result
    end

    ok = results.select { _1[:status] == :ok }
    speed = ok.map { { name: _1[:name], unit: "s", value: _1[:elapsed] } }
    coverage = ok.map do |r|
      typed, total = r[:overall].values_at(:typed, :total)
      { name: r[:name], unit: "%", value: (typed * 100.0 / total).round(2) }
    end

    gha_dir = File.join(ROOT, "tmp", "benchmark")
    FileUtils.mkdir_p(gha_dir)
    File.write(File.join(gha_dir, "speed.json"), JSON.pretty_generate(speed))
    File.write(File.join(gha_dir, "coverage.json"), JSON.pretty_generate(coverage))

    exit 1 unless ok.size == results.size
  end
end
