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
      unless source_sha == main_sha
        problems << "workflow source #{source_sha} is not main head #{main_sha}"
      end

      REQUIRED_CHECKS.each do |name|
        next if successful_check?(check_runs, name, main_sha)

        problems << "main head #{main_sha} has no successful #{name} check"
      end
      problems
    end

    def version_change_problems(changed_paths:, requested:, target_version:, version_source:)
      paths = changed_paths.reject(&:empty?).uniq.sort
      expected = requested == "skip" ? [] : [VERSION_PATH]
      problems = []
      unless paths == expected
        problems << "release commit changes #{paths.inspect}; " \
                    "expected #{expected.inspect}"
      end

      actual = version_source[/VERSION = ['"]([^'"]+)['"]/, 1]
      unless actual == target_version
        problems << "#{VERSION_PATH} contains #{actual.inspect}; " \
                    "expected #{target_version.inspect}"
      end
      problems
    end

    def replace_version(source, target_version)
      pattern = /(VERSION = )(["'])[^"']+\2/
      unless source.scan(pattern).one?
        raise ArgumentError, "expected exactly one VERSION assignment"
      end

      source.sub(pattern) { "#{Regexp.last_match(1)}\"#{target_version}\"" }
    end

    def successful_check?(check_runs, name, main_sha)
      latest = latest_check(check_runs, name, main_sha)
      latest&.values_at("status", "conclusion") == %w[completed success]
    end

    def latest_check(check_runs, name, main_sha)
      check_runs
        .select { |run| run.values_at("name", "head_sha") == [name, main_sha] }
        .max_by { |run| run.fetch("id", 0) }
    end
    private_class_method :latest_check, :successful_check?

    # Parses the small command-line interface separately from the checks.
    class CLI
      CHECKED_MAIN_USAGE =
        "usage: check_release_source.rb checked-main " \
        "SOURCE_SHA MAIN_SHA CHECKS_JSON"
      VERSION_ONLY_USAGE =
        "usage: check_release_source.rb version-only " \
        "TARGET REQUESTED PATHS_FILE [VERSION_FILE]"
      WRITE_VERSION_USAGE =
        "usage: check_release_source.rb write-version TARGET [VERSION_FILE]"

      def initialize(arguments)
        @arguments = arguments.dup
      end

      def run
        problems = problems_for(@arguments.shift)
        return puts("release source OK") if problems.empty?

        warn(*problems.map { |problem| "release source check failed: #{problem}" })
        exit 1
      end

      private

      def problems_for(mode)
        case mode
        when "checked-main" then checked_main_problems
        when "version-only" then version_change_problems
        when "write-version" then write_version
        else abort "usage: check_release_source.rb checked-main|version-only|write-version ..."
        end
      end

      def checked_main_problems
        source_sha, main_sha, checks_path = @arguments
        abort CHECKED_MAIN_USAGE unless checks_path

        payload = JSON.parse(File.read(checks_path))
        ReleaseSourceCheck.checked_main_problems(
          source_sha: source_sha,
          main_sha: main_sha,
          check_runs: payload.fetch("check_runs"),
        )
      end

      def version_change_problems
        target, requested, paths_path, version_path = @arguments
        abort VERSION_ONLY_USAGE unless paths_path

        ReleaseSourceCheck.version_change_problems(
          changed_paths: File.readlines(paths_path, chomp: true),
          requested: requested,
          target_version: target,
          version_source: File.read(version_path || ReleaseSourceCheck::VERSION_PATH),
        )
      end

      def write_version
        target, version_path = @arguments
        abort WRITE_VERSION_USAGE unless target

        path = version_path || ReleaseSourceCheck::VERSION_PATH
        source = ReleaseSourceCheck.replace_version(File.read(path), target)
        File.write(path, source)
        []
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Sirena::ReleaseSourceCheck::CLI.new(ARGV).run
end
