#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

module Sirena
  # Guards the repository-owned release workflow against publishing from an
  # unchecked commit or smuggling files into the generated version bump.
  module ReleaseSourceCheck
    REQUIRED_CHECKS = %w[fast-lane full-lane].freeze
    VERSION_PATH = "lib/sirena/version.rb"

    module_function

    def checked_main_problems(source_sha:, main_sha:, check_runs:)
      problems = []
      problems << "workflow source #{source_sha} is not main head #{main_sha}" unless source_sha == main_sha

      REQUIRED_CHECKS.each do |name|
        matching = check_runs.select { |run| run["name"] == name && run["head_sha"] == main_sha }
        latest = matching.max_by { |run| run.fetch("id", 0) }
        next if latest && latest["status"] == "completed" && latest["conclusion"] == "success"

        problems << "main head #{main_sha} has no successful #{name} check"
      end
      problems
    end

    def version_change_problems(changed_paths:, requested:, target_version:, version_source:)
      paths = changed_paths.reject(&:empty?).uniq.sort
      expected = requested == "skip" ? [] : [VERSION_PATH]
      problems = []
      problems << "release commit changes #{paths.inspect}; expected #{expected.inspect}" unless paths == expected

      actual = version_source[/VERSION = ['\"]([^'\"]+)['\"]/, 1]
      problems << "#{VERSION_PATH} contains #{actual.inspect}; expected #{target_version.inspect}" unless actual == target_version
      problems
    end

    def replace_version(source, target_version)
      pattern = /(VERSION = )(["'])[^"']+\2/
      raise ArgumentError, "expected exactly one VERSION assignment" unless source.scan(pattern).one?

      source.sub(pattern) { "#{Regexp.last_match(1)}\"#{target_version}\"" }
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  mode = ARGV.shift
  problems = case mode
             when "checked-main"
               source_sha, main_sha, checks_path = ARGV
               abort "usage: check_release_source.rb checked-main SOURCE_SHA MAIN_SHA CHECKS_JSON" unless checks_path

               payload = JSON.parse(File.read(checks_path))
               Sirena::ReleaseSourceCheck.checked_main_problems(
                 source_sha: source_sha, main_sha: main_sha, check_runs: payload.fetch("check_runs")
               )
             when "version-only"
               target, requested, paths_path, version_path = ARGV
               abort "usage: check_release_source.rb version-only TARGET REQUESTED PATHS_FILE [VERSION_FILE]" unless paths_path

               Sirena::ReleaseSourceCheck.version_change_problems(
                 changed_paths: File.readlines(paths_path, chomp: true),
                 requested: requested,
                 target_version: target,
                 version_source: File.read(version_path || Sirena::ReleaseSourceCheck::VERSION_PATH)
               )
             when "write-version"
               target, version_path = ARGV
               abort "usage: check_release_source.rb write-version TARGET [VERSION_FILE]" unless target

               path = version_path || Sirena::ReleaseSourceCheck::VERSION_PATH
               File.write(path, Sirena::ReleaseSourceCheck.replace_version(File.read(path), target))
               []
             else
               abort "usage: check_release_source.rb checked-main|version-only|write-version ..."
             end

  if problems.empty?
    puts "release source OK"
  else
    warn(*problems.map { |problem| "release source check failed: #{problem}" })
    exit 1
  end
end
