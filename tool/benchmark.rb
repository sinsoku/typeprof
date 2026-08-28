#!/usr/bin/env ruby
# frozen_string_literal: true

# Measures TypeProf against the benchmark projects.
#
# With no arguments it measures the working tree as it is — uncommitted
# changes included — prints the results as JSON, and fails if any project does
# not analyse cleanly. With --rev it replays committed history into
# benchmark_data/, one JSON file per (commit, project); that archive can be
# rebuilt at any time, and a metric or project added later can be backfilled
# over past commits.
#
#   ruby tool/benchmark.rb                      # working tree -> stdout
#   ruby tool/benchmark.rb --rev HEAD           # backfill every commit in range
#   ruby tool/benchmark.rb --rev HEAD --limit 1 # archive HEAD
#
# Commits are measured one at a time: `elapsed` is one of the metrics, and
# concurrent runs would contend for CPU and distort it. The full range takes
# about half an hour.

require "json"
require "optparse"

require_relative "benchmark/runner"

Bench = TypeProf::Bench

# `--show-stats` was added here; commits before it cannot be measured.
STATS_SINCE = "2fc33f77"

options = { force: false }

OptionParser.new do |opt|
  opt.banner = "Usage: ruby tool/benchmark.rb [options]"
  opt.on("--rev REV", "Archive commits reachable from REV instead of measuring the working tree") { options[:rev] = _1 }
  opt.on("--limit N", Integer, "Measure at most N commits, newest first") { options[:limit] = _1 }
  opt.on("--force", "Re-measure commits that already have data") { options[:force] = true }
end.parse!

# Preparing is idempotent and costs a handful of file checks once the projects
# are in place. The first run clones them and generates RBS for redmine, which
# takes several minutes.
def prepare_projects
  Bench::Projects::ALL.each do |project|
    warn "Preparing #{project.name}" unless Dir.exist?(project.dir)
    project.prepare!
  end
end

runner = Bench::Runner.new

unless options[:rev]
  abort "--limit and --force require --rev" if options[:limit] || options[:force]

  prepare_projects
  data = runner.run_working_tree
  puts JSON.pretty_generate(data)
  exit 1 unless data[:projects].all? { _1[:status] == :ok }
  exit
end

Commit = Data.define(:sha, :timestamp, :date)

def select_commits(options)
  out = Bench.git("rev-list", "--first-parent", "--format=%H %ct %cs", "--no-commit-header",
                  "#{STATS_SINCE}..#{options[:rev]}")
  list = out.lines.map do |line|
    sha, timestamp, date = line.split
    Commit.new(sha:, timestamp: timestamp.to_i, date:)
  end
  list = list.first(options[:limit]) if options[:limit]
  list.reverse # oldest first, so a partial run still builds history forward
end

targets = select_commits(options)
targets = targets.reject { runner.measured?(_1.sha) } unless options[:force]

if targets.empty?
  puts "Nothing to measure (use --force to re-measure)."
  exit
end

puts "Measuring #{targets.size} commit(s)"
prepare_projects

failures = []
targets.each do |commit|
  results = runner.run(commit.sha, timestamp: commit.timestamp, date: commit.date,
                       force: options[:force])
  summary = results.map { "#{_1[:name]}=#{_1[:status]}" }.join(" ")
  puts "#{commit.sha[0, 10]} #{commit.date}  #{summary}"
rescue => e
  failures << [commit.sha, "#{e.class}: #{e.message}"]
end

puts
puts "benchmark_data/ now holds #{Dir.glob(File.join(Bench::Runner::DATA_DIR, "*")).size} commit(s)"

unless failures.empty?
  warn "#{failures.size} commit(s) could not be measured:"
  failures.each { warn "  #{_1[0, 10]}: #{_2}" }
  exit 1
end
