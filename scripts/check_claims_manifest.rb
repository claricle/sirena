# frozen_string_literal: true

require "open3"
require "yaml"

# Validates the committed docs-claims dispositions and ensures text declared
# removed cannot reappear in tracked user-facing source.
module Sirena
  module ClaimsManifestCheck
    class GitGrepError < StandardError; end

    MANIFEST_RELPATH = "docs/claims-manifest.yml"
    DISPOSITIONS = %w[verified corrected removed].freeze
    REQUIRED_KEYS = %w[claim file disposition evidence pr].freeze
    STRING_KEYS = %w[claim file disposition evidence].freeze
    EXCLUDED_PATHSPECS = [
      ":(exclude)docs/plans",
      ":(exclude)TODO.foundation",
      ":(exclude)_site",
      ":(exclude)#{MANIFEST_RELPATH}",
      ":(exclude)spec/scripts/check_claims_manifest_spec.rb",
    ].freeze

    module_function

    def rows(manifest_path)
      loaded = YAML.safe_load_file(manifest_path)
      unless loaded.is_a?(Array) && !loaded.empty?
        raise ArgumentError,
              "#{manifest_path}: expected a non-empty YAML list of rows"
      end

      loaded.each_with_index do |row, index|
        validate_row!(row, index, manifest_path)
      end
      loaded
    end

    def validate_row!(row, index, manifest_path)
      unless row.is_a?(Hash)
        raise ArgumentError, "#{manifest_path}: row #{index} is not a mapping"
      end

      missing = REQUIRED_KEYS - row.keys
      unless missing.empty?
        raise ArgumentError,
              "#{manifest_path}: row #{index} missing #{missing.join(', ')}"
      end

      unexpected = row.keys - REQUIRED_KEYS
      unless unexpected.empty?
        raise ArgumentError,
              "#{manifest_path}: row #{index} has unknown keys " \
              "#{unexpected.join(', ')}"
      end

      invalid_strings = STRING_KEYS.reject do |key|
        row[key].is_a?(String) && !row[key].strip.empty?
      end
      unless invalid_strings.empty?
        raise ArgumentError,
              "#{manifest_path}: row #{index} " \
              "#{invalid_strings.join(', ')} must be non-empty strings"
      end

      unless row["pr"].is_a?(Integer) && row["pr"].positive?
        raise ArgumentError,
              "#{manifest_path}: row #{index} pr must be a positive Integer"
      end
      unless DISPOSITIONS.include?(row["disposition"])
        raise ArgumentError,
              "#{manifest_path}: row #{index} has disposition " \
              "#{row['disposition'].inspect}, " \
              "want one of #{DISPOSITIONS.join(', ')}"
      end
      return unless row["claim"].include?("\n")

      raise ArgumentError,
            "#{manifest_path}: row #{index} claim must not contain a newline"
    end

    def problems(root: ".")
      manifest_path = File.join(root, MANIFEST_RELPATH)
      rows(manifest_path).select { |row| row["disposition"] == "removed" }
        .filter_map { |row| removed_row_problem(row, root) }
    end

    def removed_row_problem(row, root)
      return unless present_in_tracked_source?(row.fetch("claim"), root)

      "claim marked removed still appears in tracked source: " \
        "#{row['claim'].inspect} (was #{row['file']})"
    end

    def present_in_tracked_source?(claim, root)
      _output, error, status = Open3.capture3(
        "git", "-C", root, "grep", "-F", "-I", "-q", "-e", claim,
        "--", ".", *EXCLUDED_PATHSPECS
      )

      case status.exitstatus
      when 0 then true
      when 1 then false
      else raise GitGrepError, "git grep failed: #{error.strip}"
      end
    end

    def report!(root:)
      found = problems(root: root)
    rescue ArgumentError, SystemCallError, GitGrepError, Psych::Exception => e
      warn "claims manifest check failed: #{e.message}"
      false
    else
      if found.empty?
        puts "claims manifest: clean"
        true
      else
        messages = found.map do |problem|
          "claims manifest check failed: #{problem}"
        end
        warn(*messages)
        false
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  root = File.expand_path("..", __dir__)
  exit(Sirena::ClaimsManifestCheck.report!(root: root) ? 0 : 1)
end
