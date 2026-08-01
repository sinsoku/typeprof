#!/usr/bin/env ruby
# frozen_string_literal: true

# Clones and sets up the benchmark corpus under tmp/bench_corpus.
#
# Run once per project. Backfilling replays this corpus over many TypeProf
# commits, so setup must not happen on every measurement.
#
#   ruby tool/bench/prepare.rb              # all projects
#   ruby tool/bench/prepare.rb optcarrot    # only the named ones

require_relative "corpus"

include TypeProf::Bench # rubocop:disable Style/MixinUsage

names = ARGV.empty? ? Corpus.all.map(&:name) : ARGV
projects = names.map { Corpus.fetch(_1) }

projects.each do |project|
  puts "==> #{project.name} (#{project.ref})"
  project.prepare!

  missing = project.targets.reject { File.exist?(File.join(project.dir, _1)) }
  warn "    WARNING: missing targets: #{missing.join(", ")}" unless missing.empty?
  puts "    #{project.dir}"
end

puts
puts "Prepared #{projects.size} project(s) under #{CORPUS_DIR}"
