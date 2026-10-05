# frozen_string_literal: true

# svg_conform is a Gemfile-only development dependency, so this lives under
# tasks/ and is required only from tasks/conformance.rake and its spec,
# never from lib/.
require "date"
require "fileutils"
require "json"
require "rexml/document"
require "svg_conform"
require "timeout"
require "sirena"

module Sirena
  # The conformance column of the scoreboard: one row per corpus case that
  # renders to an SVG document, saying whether that SVG is well-formed XML
  # and valid under Sirena::Svg::CONFORMANCE_PROFILE. A case that does not
  # render has no document to judge and no row; its status is
  # scoreboard/corpus.json's.
  #
  # Rows, never a count: fixing case A while breaking case B must still fail.
  module Conformance
    # A conformant case that stops being conformant, or stops rendering.
    class RegressionError < StandardError; end

    ROOT = File.expand_path("../..", __dir__)
    CORPUS_ROOT = File.join(ROOT, "spec", "mermaid")
    SCOREBOARD_PATH = File.join(ROOT, "scoreboard", "conformance.json")

    CONFORMANT = "conformant"
    NONCONFORMANT = "nonconformant"
    STATUSES = [CONFORMANT, NONCONFORMANT].freeze

    CASE_TIMEOUT = 10
    # Gantt bars are placed relative to today, so an unpinned render judges a
    # different document every day. Same date spec/svg_conformance_spec.rb pins.
    TODAY = Date.new(2026, 1, 1)

    module_function

    def cases
      Dir.glob(File.join(CORPUS_ROOT, "*", "*.mmd")).map do |path|
        path.delete_prefix("#{CORPUS_ROOT}/")
      end
    end

    # svg_conform does not reject malformed XML and accepts a bare `<rect/>`,
    # so a document that is not well-formed XML with an <svg> root is
    # rejected here first.
    def status_for(svg)
      return NONCONFORMANT unless svg_document?(svg)

      if SvgConform.validate(svg,
                             profile: Svg::CONFORMANCE_PROFILE).valid?
        CONFORMANT
      else
        NONCONFORMANT
      end
    end

    def svg_document?(svg)
      REXML::Document.new(svg).root&.name == "svg"
    rescue REXML::ParseException
      false
    end

    # The SVG a case renders to, or nil when rendering raises or times out.
    def render(relative_path)
      source = File.read(File.join(CORPUS_ROOT, relative_path))
      Timeout.timeout(CASE_TIMEOUT) do
        Engine.new.render(source, today: TODAY)
      end
    rescue StandardError
      nil
    end

    def rows(paths = cases)
      paths.filter_map do |path|
        svg = render(path)
        { "case" => path, "status" => status_for(svg) } if svg
      end
    end

    # Renamed into place, so a run killed mid-write never leaves a truncated
    # scoreboard; the PID keeps two overlapping runs off the same temp file.
    def write_scoreboard(rows)
      tmp_path = "#{SCOREBOARD_PATH}.#{Process.pid}.tmp"
      File.write(tmp_path, "#{JSON.pretty_generate(rows)}\n")
      File.rename(tmp_path, SCOREBOARD_PATH)
    ensure
      FileUtils.rm_f(tmp_path)
    end

    # The committed file is hand-mergeable input. A row the comparison cannot
    # read would resolve to the same nil as an absent case and hide a change,
    # and a repeated case would let the later row hide the earlier one.
    def load_scoreboard
      rows = parse_scoreboard
      reject_unreadable(rows)
      reject_malformed(rows)
      reject_duplicated(rows)
      rows
    end

    def reject_unreadable(rows)
      return if rows.is_a?(Array) && rows.all?(Hash)

      raise RegressionError, "#{SCOREBOARD_PATH} is not a list of rows"
    end

    def reject_malformed(rows)
      malformed = rows.reject do |row|
        row["case"].is_a?(String) && STATUSES.include?(row["status"])
      end
      return if malformed.empty?

      raise RegressionError,
            "#{SCOREBOARD_PATH} has malformed rows: " \
            "#{malformed.map(&:inspect).join(', ')}"
    end

    def reject_duplicated(rows)
      names = rows.map { |row| row["case"] }
      duplicated = names.tally.select { |_, count| count > 1 }.keys
      return if duplicated.empty?

      raise RegressionError,
            "#{SCOREBOARD_PATH} has more than one row for: " \
            "#{duplicated.sort.join(', ')}"
    end

    def parse_scoreboard
      JSON.parse(File.read(SCOREBOARD_PATH))
    rescue JSON::ParserError => e
      raise RegressionError,
            "#{SCOREBOARD_PATH} is not valid JSON: #{e.message}"
    end

    # A case regresses when it was recorded conformant and is not now,
    # including when it no longer renders. Any other difference between the
    # two files -- a case that became conformant, or a nonconformant row
    # that appeared or vanished -- makes the file stale, and a stale file
    # lets the next regression of that case go unseen.
    def diff(committed_rows, fresh_rows)
      before = status_by_case(committed_rows)
      after = status_by_case(fresh_rows)
      changed = (before.keys | after.keys).reject do |name|
        before[name] == after[name]
      end
      regressed = changed.select { |name| before[name] == CONFORMANT }

      { regressed: regressed.sort, stale: (changed - regressed).sort }
    end

    def status_by_case(rows)
      rows.to_h { |row| [row["case"], row["status"]] }
    end

    def conformant_cases(rows)
      rows.select do |row|
        row["status"] == CONFORMANT
      end.map { |row| row["case"] }
    end

    def summary(rows)
      conformant = conformant_cases(rows).size
      rate = rows.empty? ? 0.0 : 100.0 * conformant / rows.size
      percent = format("%.1f", rate)
      "conformance: #{conformant}/#{rows.size} rendered cases " \
        "conformant (#{percent}%)"
    end

    def record!
      fresh = rows
      if fresh.empty?
        raise RegressionError,
              "no corpus case rendered; keeping #{SCOREBOARD_PATH}"
      end

      write_scoreboard(fresh)
      "#{summary(fresh)}\nwrote #{SCOREBOARD_PATH}"
    end

    def check!(fresh = nil)
      unless File.exist?(SCOREBOARD_PATH)
        raise RegressionError,
              "#{SCOREBOARD_PATH} is missing; run `rake conformance` first."
      end

      committed = load_scoreboard
      fresh ||= rows
      drift = diff(committed, fresh)
      raise RegressionError, drift_message(drift) if drift.values.any?(&:any?)

      "conformance:check: clean (#{summary(fresh)})"
    end

    STALE_HEADING = "STALE (differs from the committed scoreboard; run " \
                    "`rake conformance` and commit " \
                    "scoreboard/conformance.json):"
    REGRESSED_HEADING =
      "REGRESSED (conformant in the committed scoreboard, not now):"

    def drift_message(drift)
      sections = [[REGRESSED_HEADING, drift[:regressed]],
                  [STALE_HEADING, drift[:stale]]]
      sections.reject { |_, names| names.empty? }.flat_map do |heading, names|
        [heading, *names.map { |name| "  #{name}" }]
      end.join("\n")
    end
  end
end
