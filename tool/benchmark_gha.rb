#!/usr/bin/env ruby
# frozen_string_literal: true

# Converts `tool/benchmark.rb` output into github-action-benchmark's custom
# tool format, one file per suite:
#
#   tmp/benchmark/speed.json     (customSmallerIsBetter, seconds)
#   tmp/benchmark/coverage.json  (customBiggerIsBetter, typed slots %)
#
#   ruby tool/benchmark.rb > benchmark-result.json
#   ruby tool/benchmark_gha.rb benchmark-result.json

require "fileutils"
require "json"

OUT_DIR = File.expand_path("../tmp/benchmark", __dir__)

projects = JSON.parse(ARGF.read).fetch("projects").select { _1["status"] == "ok" }

speed = projects.map { { name: _1["name"], unit: "s", value: _1["elapsed"] } }
coverage = projects.map do |p|
  typed, total = p["overall"].values_at("typed", "total")
  { name: p["name"], unit: "%", value: (typed * 100.0 / total).round(2) }
end

FileUtils.mkdir_p(OUT_DIR)
File.write(File.join(OUT_DIR, "speed.json"), JSON.pretty_generate(speed))
File.write(File.join(OUT_DIR, "coverage.json"), JSON.pretty_generate(coverage))
warn "#{OUT_DIR}/{speed,coverage}.json: #{projects.size} project(s)"
