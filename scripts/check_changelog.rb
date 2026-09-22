#!/usr/bin/env ruby
# frozen_string_literal: true

# Release preflight: is there a changelog entry for the version about to ship?
#
#   ruby scripts/check_changelog.rb <next_version> [CHANGELOG.md] [lib/sirena/version.rb]
#
# <next_version> is the release workflow's input: x.y.z, major, minor, patch
# or skip (release the version already in version.rb). pre/rc/etc are refused,
# because the changelog must name the exact version.
#
# Releasable means: a `## [X.Y.Z] - YYYY-MM-DD` section exists for the target
# version and holds at least one bullet under an allowed category heading.
module Sirena
  module ChangelogCheck
    CATEGORIES = %w[Added Changed Deprecated Removed Fixed Security].freeze
    SECTION = /\A## \[(?<version>[^\]]+)\](?: - (?<date>\d{4}-\d{2}-\d{2}))?\s*\z/
    BUMPS = %w[major minor patch].freeze

    module_function

    def target_version(next_version, current)
      return current if next_version == "skip"

      segments = Gem::Version.new(current).segments
      case next_version
      when "major" then [segments[0] + 1, 0, 0].join(".")
      when "minor" then [segments[0], segments[1] + 1, 0].join(".")
      when "patch" then [segments[0], segments[1], segments[2] + 1].join(".")
      when /\A\d+\.\d+\.\d+\z/ then next_version
      else raise ArgumentError, "next_version must be x.y.z, major, minor, patch or skip: #{next_version.inspect}"
      end
    end

    # Returns a list of problems; empty means releasable.
    def problems(changelog, version)
      section = section_lines(changelog, version)
      return ["no `## [#{version}] - YYYY-MM-DD` section in the changelog"] unless section

      problems = []
      problems << "section [#{version}] has no date" unless section[:dated]
      problems << "section [#{version}] has no bullet under #{CATEGORIES.join(', ')}" unless entry?(section[:lines])
      problems
    end

    def section_lines(changelog, version)
      lines = changelog.lines.map(&:chomp)
      start = lines.index { |l| SECTION.match(l)&.[](:version) == version }
      return nil unless start

      rest = lines[(start + 1)..]
      stop = rest.index { |l| l.start_with?("## ") } || rest.size
      { lines: rest.first(stop), dated: !SECTION.match(lines[start])[:date].nil? }
    end

    def entry?(lines)
      category = nil
      lines.any? do |line|
        heading = line[/\A### (.+?)\s*\z/, 1]
        category = heading if heading
        !heading && CATEGORIES.include?(category) && line.match?(/\A[-*] \S/)
      end
    end

    def current_version(path)
      File.read(path)[/VERSION = ['"]([^'"]+)['"]/, 1] or raise ArgumentError, "no VERSION in #{path}"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  next_version, changelog_path, version_path = ARGV
  abort "usage: check_changelog.rb <next_version> [CHANGELOG.md] [version.rb]" unless next_version

  begin
    current = Sirena::ChangelogCheck.current_version(version_path || "lib/sirena/version.rb")
    target = Sirena::ChangelogCheck.target_version(next_version, current)
    found = Sirena::ChangelogCheck.problems(File.read(changelog_path || "CHANGELOG.md"), target)
  rescue ArgumentError, SystemCallError => e
    abort "changelog check failed: #{e.message}"
  end

  if found.empty?
    puts "changelog OK for #{target}"
  else
    warn(*found.map { |p| "changelog check failed: #{p}" })
    exit 1
  end
end
