#!/usr/bin/env ruby
# frozen_string_literal: true

# Replays the benchmark corpus over TypeProf's git history and stores one JSON
# file per commit under bench_data/.
#
# Data collection is deliberately independent of CI: history can be rebuilt at
# any time, and a metric added later can be backfilled over past commits.
#
#   ruby tool/bench/prepare.rb                       # once, to set up the corpus
#   ruby tool/backfill_bench.rb --limit 1            # measure HEAD
#   ruby tool/backfill_bench.rb --sampling monthly   # one commit per month
#   ruby tool/backfill_bench.rb                      # every commit in range
#
# Runs serially by default because `elapsed` is one of the metrics and parallel
# runs contend for CPU. `--jobs N` is for refilling coverage numbers, where the
# timing is not the point; the value is recorded in each JSON file so the data
# stays interpretable.

require "optparse"
require "set"

require_relative "bench/runner"

include TypeProf::Bench # rubocop:disable Style/MixinUsage

# `--show-stats` was added here; commits before it cannot be measured.
STATS_SINCE = "2fc33f77"

options = {
  rev: "HEAD",
  sampling: "all",
  jobs: 1,
  timeout: 600,
  force: false,
  projects: nil,
}

OptionParser.new do |opt|
  opt.banner = "Usage: ruby tool/backfill_bench.rb [options]"
  opt.on("--rev REV", "Measure commits reachable from REV (default: HEAD)") { options[:rev] = _1 }
  opt.on("--sampling MODE", %w[all monthly tags], "all (default) / monthly / tags") { options[:sampling] = _1 }
  opt.on("--since DATE", "Only commits on or after DATE") { options[:since] = _1 }
  opt.on("--until DATE", "Only commits on or before DATE") { options[:until] = _1 }
  opt.on("--limit N", Integer, "Measure at most N commits, newest first") { options[:limit] = _1 }
  opt.on("--projects LIST", Array, "Comma-separated project names") { options[:projects] = _1 }
  opt.on("--jobs N", Integer, "Measure N commits concurrently (default: 1)") { options[:jobs] = _1 }
  opt.on("--timeout SEC", Integer, "Per-project timeout in seconds (default: 600)") { options[:timeout] = _1 }
  opt.on("--force", "Re-measure commits that already have data") { options[:force] = true }
end.parse!

Commit = Data.define(:sha, :timestamp, :date)

def select_commits(options)
  args = ["rev-list", "--first-parent", "--format=%H %ct %cs", "--no-commit-header",
          "#{STATS_SINCE}..#{options[:rev]}"]
  args << "--since=#{options[:since]}" if options[:since]
  args << "--until=#{options[:until]}" if options[:until]

  list = git(*args).lines.map { Commit.new(*_1.split(" ").then { |s, t, d| [s, t.to_i, d] }) }
  list = sample(list, options[:sampling])
  list = list.first(options[:limit]) if options[:limit]
  list.reverse # oldest first, so a partial run still builds history forward
end

def sample(list, mode)
  case mode
  when "all" then list
  when "monthly" then list.uniq { _1.date[0, 7] } # newest commit of each month
  when "tags"
    # Both lightweight (objectname) and annotated (*objectname) tags.
    # `git tag --format` writes a newline as %0a; %n is not interpreted here.
    tagged = git("tag", "--format=%(objectname)%0a%(*objectname)").lines.map(&:strip).to_set
    list.select { tagged.include?(_1.sha) }
  end
end

runner = Runner.new(
  projects: options[:projects] ? options[:projects].map { Corpus.fetch(_1) } : Corpus::ALL,
  timeout: options[:timeout],
  jobs: options[:jobs],
)

targets = select_commits(options)
targets = targets.reject { runner.measured?(_1.sha) } unless options[:force]

if targets.empty?
  puts "Nothing to measure (use --force to re-measure)."
  exit
end

puts "Measuring #{targets.size} commit(s) with #{options[:jobs]} job(s)"

queue = Queue.new
targets.each { queue << _1 }
queue.close
failures = []
mutex = Mutex.new

workers = Array.new([options[:jobs], targets.size].min) do
  Thread.new do
    while (commit = queue.pop)
      begin
        data = runner.run(commit.sha, timestamp: commit.timestamp, date: commit.date)
        summary = data[:error] || data[:projects].map { "#{_1[:name]}=#{_1[:status]}" }.join(" ")
        mutex.synchronize { puts "#{commit.sha[0, 10]} #{commit.date}  #{summary}" }
      rescue => e
        mutex.synchronize { failures << [commit.sha, "#{e.class}: #{e.message}"] }
      end
    end
  end
end
workers.each(&:join)

puts
puts "bench_data/ now holds #{Dir.glob(File.join(Runner::DATA_DIR, "*.json")).size} file(s)"

unless failures.empty?
  warn "#{failures.size} commit(s) could not be measured:"
  failures.each { warn "  #{_1[0, 10]}: #{_2}" }
  exit 1
end
