#!/usr/bin/env ruby
# frozen_string_literal: true

# Measures TypeProf against the benchmark projects.
#
# Analyses the working tree as it is — uncommitted changes included — prints
# the results as JSON, and fails if any project does not analyse cleanly.
#
#   ruby tool/benchmark.rb > tmp/benchmark/result.json

require "json"

require_relative "benchmark/runner"

# The first run clones the projects, which takes a minute or so; after that
# this is one directory check per project.
TypeProf::Benchmark::PROJECTS.each do |project|
  warn "Preparing #{project.name}" unless Dir.exist?(project.dir)
  project.prepare!
end

data = TypeProf::Benchmark::Runner.new.run_working_tree
puts JSON.pretty_generate(data)
exit 1 unless data[:projects].all? { _1[:status] == :ok }
