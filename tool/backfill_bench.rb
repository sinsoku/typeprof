#!/usr/bin/env ruby
# frozen_string_literal: true

# Replays the benchmark projects over TypeProf's git history and stores one
# JSON file per commit under bench_data/.
#
# Data collection is deliberately independent of CI: history can be rebuilt at
# any time, and a metric added later can be backfilled over past commits.
#
#   ruby tool/bench/prepare.rb              # once, to set the projects up
#   ruby tool/backfill_bench.rb --limit 1   # measure HEAD
#   ruby tool/backfill_bench.rb             # every commit in range
#
# Commits are measured one at a time: `elapsed` is one of the metrics, and
# concurrent runs would contend for CPU and distort it. The full range takes
# about half an hour.

require "optparse"

require_relative "bench/runner"

Bench = TypeProf::Bench

# `--show-stats` was added here; commits before it cannot be measured.
STATS_SINCE = "2fc33f77"

options = { rev: "HEAD", force: false }

OptionParser.new do |opt|
  opt.banner = "Usage: ruby tool/backfill_bench.rb [options]"
  opt.on("--rev REV", "Measure commits reachable from REV (default: HEAD)") { options[:rev] = _1 }
  opt.on("--limit N", Integer, "Measure at most N commits, newest first") { options[:limit] = _1 }
  opt.on("--force", "Re-measure commits that already have data") { options[:force] = true }
end.parse!

Commit = Data.define(:sha, :timestamp, :date)

def select_commits(options)
  out = Bench.git("rev-list", "--first-parent", "--format=%H %ct %cs", "--no-commit-header",
                  "#{STATS_SINCE}..#{options[:rev]}")
  list = out.lines.map { Commit.new(*_1.split(" ").then { |s, t, d| [s, t.to_i, d] }) }
  list = list.first(options[:limit]) if options[:limit]
  list.reverse # oldest first, so a partial run still builds history forward
end

runner = Bench::Runner.new

targets = select_commits(options)
targets = targets.reject { runner.measured?(_1.sha) } unless options[:force]

if targets.empty?
  puts "Nothing to measure (use --force to re-measure)."
  exit
end

puts "Measuring #{targets.size} commit(s)"

failures = targets.filter_map do |commit|
  data = runner.run(commit.sha, timestamp: commit.timestamp, date: commit.date)
  summary = data[:error] || data[:projects].map { "#{_1[:name]}=#{_1[:status]}" }.join(" ")
  puts "#{commit.sha[0, 10]} #{commit.date}  #{summary}"
  nil
rescue => e
  [commit.sha, "#{e.class}: #{e.message}"]
end

puts
puts "bench_data/ now holds #{Dir.glob(File.join(Bench::Runner::DATA_DIR, "*.json")).size} file(s)"

unless failures.empty?
  warn "#{failures.size} commit(s) could not be measured:"
  failures.each { warn "  #{_1[0, 10]}: #{_2}" }
  exit 1
end
