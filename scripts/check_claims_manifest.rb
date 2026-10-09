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
      ":(exclude)spec/sirena/claims_manifest_check_spec.rb",
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
      context = "#{manifest_path}: row #{index}"
      validate_mapping!(row, context)
      validate_keys!(row, context)
      validate_strings!(row, context)
      validate_pr!(row, context)
      validate_disposition!(row, context)
      validate_claim!(row, context)
    end

    def validate_mapping!(row, context)
      return if row.is_a?(Hash)

      raise ArgumentError, "#{context} is not a mapping"
    end

    def validate_keys!(row, context)
      missing = REQUIRED_KEYS - row.keys
      raise ArgumentError, "#{context} missing #{missing.join(', ')}" if missing.any?

      unexpected = row.keys - REQUIRED_KEYS
      return if unexpected.empty?

      raise ArgumentError, "#{context} has unknown keys #{unexpected.join(', ')}"
    end

    def validate_strings!(row, context)
      invalid = STRING_KEYS.reject { |key| present_string?(row[key]) }
      return if invalid.empty?

      raise ArgumentError, "#{context} #{invalid.join(', ')} must be non-empty strings"
    end

    def present_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def validate_pr!(row, context)
      return if row["pr"].is_a?(Integer) && row["pr"].positive?

      raise ArgumentError, "#{context} pr must be a positive Integer"
    end

    def validate_disposition!(row, context)
      disposition = row["disposition"]
      return if DISPOSITIONS.include?(disposition)

      raise ArgumentError,
            "#{context} has disposition #{disposition.inspect}, " \
            "want one of #{DISPOSITIONS.join(', ')}"
    end

    def validate_claim!(row, context)
      return unless row["claim"].include?("\n")

      raise ArgumentError, "#{context} claim must not contain a newline"
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
      report_problems(found)
    end

    def report_problems(found)
      return report_clean if found.empty?

      warn(*found.map { |problem| "claims manifest check failed: #{problem}" })
      false
    end

    def report_clean
      puts "claims manifest: clean"
      true
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  root = File.expand_path("..", __dir__)
  exit(Sirena::ClaimsManifestCheck.report!(root: root) ? 0 : 1)
end
