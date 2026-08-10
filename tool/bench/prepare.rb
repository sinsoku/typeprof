#!/usr/bin/env ruby
# frozen_string_literal: true

# Clones and sets up the benchmark projects under tmp/bench_projects.
#
# Run once per project. Backfilling replays them over many TypeProf commits, so
# setup must not happen on every measurement.
#
#   ruby tool/bench/prepare.rb              # all projects
#   ruby tool/bench/prepare.rb optcarrot    # only the named ones

require_relative "projects"

Bench = TypeProf::Bench

projects = ARGV.empty? ? Bench::Projects::ALL : ARGV.map { Bench::Projects.fetch(_1) }

projects.each do |project|
  puts "==> #{project.name} (#{project.ref})"
  project.prepare!

  missing = project.targets.reject { File.exist?(File.join(project.dir, _1)) }
  warn "    WARNING: missing targets: #{missing.join(", ")}" unless missing.empty?
  puts "    #{project.dir}"
end

puts
puts "Prepared #{projects.size} project(s) under #{Bench::PROJECTS_DIR}"
