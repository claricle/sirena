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
      Dir.glob(File.join(CORPUS_ROOT, "*", "*.mmd")).map { |path| path.delete_prefix("#{CORPUS_ROOT}/") }
    end

    # svg_conform does not reject malformed XML and accepts a bare `<rect/>`, so a document
    # that is not well-formed XML with an <svg> root is rejected here first.
    def status_for(svg)
      return NONCONFORMANT unless svg_document?(svg)

      SvgConform.validate(svg, profile: Svg::CONFORMANCE_PROFILE).valid? ? CONFORMANT : NONCONFORMANT
    end

    def svg_document?(svg)
      REXML::Document.new(svg).root&.name == "svg"
    rescue REXML::ParseException
      false
    end

    # The SVG a case renders to, or nil when rendering raises or times out.
    def render(relative_path)
      source = File.read(File.join(CORPUS_ROOT, relative_path))
      Timeout.timeout(CASE_TIMEOUT) { Engine.new.render(source, today: TODAY) }
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
      raise RegressionError, "#{SCOREBOARD_PATH} is not a list of rows" unless rows.is_a?(Array) && rows.all?(Hash)

      malformed = rows.reject { |row| row["case"].is_a?(String) && STATUSES.include?(row["status"]) }
      raise RegressionError, "#{SCOREBOARD_PATH} has malformed rows: #{malformed.map(&:inspect).join(', ')}" if malformed.any?

      duplicated = rows.map { |row| row["case"] }.tally.select { |_, count| count > 1 }.keys
      raise RegressionError, "#{SCOREBOARD_PATH} has more than one row for: #{duplicated.sort.join(', ')}" if duplicated.any?

      rows
    end

    def parse_scoreboard
      JSON.parse(File.read(SCOREBOARD_PATH))
    rescue JSON::ParserError => e
      raise RegressionError, "#{SCOREBOARD_PATH} is not valid JSON: #{e.message}"
    end

    # A case regresses when it was recorded conformant and is not now,
    # including when it no longer renders. Any other difference between the
    # two files -- a case that became conformant, or a nonconformant row
    # that appeared or vanished -- makes the file stale, and a stale file
    # lets the next regression of that case go unseen.
    def diff(committed_rows, fresh_rows)
      before = status_by_case(committed_rows)
      after = status_by_case(fresh_rows)
      changed = (before.keys | after.keys).reject { |name| before[name] == after[name] }
      regressed = changed.select { |name| before[name] == CONFORMANT }

      { regressed: regressed.sort, stale: (changed - regressed).sort }
    end

    def status_by_case(rows)
      rows.to_h { |row| [row["case"], row["status"]] }
    end

    def conformant_cases(rows)
      rows.select { |row| row["status"] == CONFORMANT }.map { |row| row["case"] }
    end

    def summary(rows)
      conformant = conformant_cases(rows).size
      rate = rows.empty? ? 0.0 : 100.0 * conformant / rows.size
      format("conformance: %d/%d rendered cases conformant (%.1f%%)", conformant, rows.size, rate)
    end

    def record!
      fresh = rows
      raise RegressionError, "no corpus case rendered; keeping #{SCOREBOARD_PATH}" if fresh.empty?

      write_scoreboard(fresh)
      "#{summary(fresh)}\nwrote #{SCOREBOARD_PATH}"
    end

    def check!(fresh = nil)
      raise RegressionError, "#{SCOREBOARD_PATH} is missing; run `rake conformance` first." unless File.exist?(SCOREBOARD_PATH)

      committed = load_scoreboard
      fresh ||= rows
      drift = diff(committed, fresh)
      raise RegressionError, drift_message(drift) if drift.values.any?(&:any?)

      "conformance:check: clean (#{summary(fresh)})"
    end

    def drift_message(drift)
      [
        ["REGRESSED (conformant in the committed scoreboard, not now):", drift[:regressed]],
        ["STALE (differs from the committed scoreboard; run `rake conformance` and commit " \
         "scoreboard/conformance.json):", drift[:stale]]
      ].reject { |_, names| names.empty? }
        .flat_map { |heading, names| [heading, *names.map { |name| "  #{name}" }] }
        .join("\n")
    end
  end
end
