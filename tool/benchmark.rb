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
#   => tmp/benchmark/analysis_time.json  (customSmallerIsBetter, seconds)
#   => tmp/benchmark/type_coverage.json  (customBiggerIsBetter, typed slots %)

require_relative "benchmark/runner"

exit 1 unless TypeProf::Benchmark.run
