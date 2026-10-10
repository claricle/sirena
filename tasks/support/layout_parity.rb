# frozen_string_literal: true

require "json"
require "tempfile"
require "sirena"

Dir[File.expand_path("../../spec/support/layout_parity/*.rb", __dir__)]
  .each { |path| require path }

module Sirena
  # Generates and checks the live per-case layout parity scoreboard.
  module LayoutParityScoreboard
    class DriftError < StandardError; end

    ROOT = File.expand_path("../..", __dir__)
    SCOREBOARD_PATH = File.join(ROOT, "scoreboard", "layout-parity.json")
    ACTION = "run `bundle exec rake layout_parity` and commit " \
             "scoreboard/layout-parity.json"

    module_function

    def measure(runner = SpecSupport::LayoutParity::CohortRunner.new)
      results = runner.run
      SpecSupport::LayoutParity::CaseLedger.build(results)
    end

    def record!(fresh: nil, path: SCOREBOARD_PATH)
      rows = fresh || measure
      reject_empty(rows, path)
      write_scoreboard(rows, path: path)
      "layout_parity: recorded #{summary(rows)} in #{path}"
    end

    def check!(fresh: nil, path: SCOREBOARD_PATH)
      committed = load_scoreboard(path: path)
      rows = fresh || measure
      reject_empty(rows, path)
      drift = SpecSupport::LayoutParity::ScoreboardRatchet.diff(
        committed: committed,
        fresh: rows,
      )
      raise DriftError, drift_message(drift) if drift.values.any?(&:any?)

      "layout_parity:check: clean (#{summary(rows)})"
    end

    def load_scoreboard(path: SCOREBOARD_PATH)
      rows = JSON.parse(File.read(path))
      unless rows.is_a?(Array) && rows.all?(Hash)
        raise DriftError, "#{path} is not a list of parity rows"
      end

      validate_scoreboard(rows, path)
      rows
    rescue Errno::ENOENT
      raise DriftError, "#{path} is missing; #{ACTION}."
    rescue JSON::ParserError => e
      raise DriftError, "#{path} is not valid JSON: #{e.message}"
    end

    def validate_scoreboard(rows, path)
      SpecSupport::LayoutParity::ScoreboardRatchet.diff(
        committed: rows,
        fresh: rows,
      )
    rescue ArgumentError, KeyError => e
      raise DriftError, "#{path} has invalid parity rows: #{e.message}"
    end

    def write_scoreboard(rows, path: SCOREBOARD_PATH)
      directory = File.dirname(path)
      prefix = "#{File.basename(path)}."
      Tempfile.create([prefix, ".tmp"], directory) do |file|
        file.chmod(0o644)
        file.write("#{JSON.pretty_generate(rows)}\n")
        file.flush
        file.fsync
        file.close
        File.rename(file.path, path)
      end
    end

    def summary(rows)
      hard_failures = rows.count { |row| row.dig("summary", "hard_failure") }
      analogs = rows.count do |row|
        !row.dig("summary", "metrics", "worst_analog").nil?
      end
      "#{rows.size} cases, #{hard_failures} hard failures, " \
        "#{analogs} analog cases"
    end

    def reject_empty(rows, path)
      return unless rows.empty?

      raise DriftError, "no parity cases measured; keeping #{path}"
    end

    def drift_message(drift)
      sections = drift_sections(drift).compact
      "#{sections.join("\n")}\n#{ACTION}."
    end

    def drift_sections(drift)
      [
        names_section("MISSING FROM FRESH MEASUREMENT:", drift[:missing]),
        names_section("NEW CASES NOT RECORDED:", drift[:new]),
        changes_section("REGRESSIONS:", drift[:regressions]),
        changes_section("IMPROVEMENTS NOT RECORDED:",
                        drift[:unrecorded_improvements]),
        names_section("STALE EVIDENCE:", drift[:stale]),
      ]
    end

    def names_section(heading, names)
      return if names.empty?

      ([heading] + names.map { |name| "  #{name}" }).join("\n")
    end

    def changes_section(heading, changes)
      return if changes.empty?

      lines = changes.map do |change|
        "  #{change[:case]} #{change[:field]}: " \
          "#{change[:before].inspect} -> #{change[:after].inspect}"
      end
      ([heading] + lines).join("\n")
    end
  end
end
