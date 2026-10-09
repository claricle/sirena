# frozen_string_literal: true

require "json"
require "yaml"
require "timeout"
require "fileutils"

# Measures scoreboard/plantuml.json: a case passes when the pinned oracle
# calls it valid AND Sirena renders it to well-formed SVG by the predicate
# scripts/corpus_sweep.rb applies to the Mermaid corpus. `check!` fails when
# the committed file differs from a fresh measurement.
module PlantumlScoreboard
  ROOT = File.expand_path("..", __dir__)
  CORPUS_ROOT = File.join(ROOT, "spec/plantuml")
  VERDICTS_PATH = File.join(CORPUS_ROOT, "oracle-verdicts.yml")
  SCOREBOARD_PATH = File.join(ROOT, "scoreboard/plantuml.json")
  CASE_TIMEOUT = 10
  MEASURED = %w[cases oracle_valid passing pass_rate status].freeze

  module_function

  # The corpus_sweep.rb predicate, loaded into its own namespace so its
  # top-level helpers do not land on Object.
  def predicate
    @predicate ||= begin
      namespace = Module.new
      load File.join(ROOT, "scripts/corpus_sweep.rb"), namespace
      Object.new.extend(namespace)
    end
  end

  def verdicts
    YAML.load_file(VERDICTS_PATH).fetch("verdicts")
      .to_h { |record| [record.fetch("id"), record.fetch("verdict")] }
  end

  def renders?(source)
    svg = Timeout.timeout(CASE_TIMEOUT) do
      Sirena.render(source, notation: :plantuml)
    end
    predicate.send(:well_formed_svg?, svg)
  rescue StandardError
    false
  end

  def measure(type, verdict_by_id)
    paths = Dir.glob(File.join(CORPUS_ROOT, type, "*.puml"))
    valid = paths.select { |path| oracle_valid?(type, path, verdict_by_id) }
    passing = valid.count { |path| renders?(File.read(path)) }
    summarize(paths.size, valid.size, passing)
  end

  def oracle_valid?(type, path, verdict_by_id)
    verdict_by_id["#{type}/#{File.basename(path, '.puml')}"] == "valid"
  end

  def summarize(cases, oracle_valid, passing)
    rate = oracle_valid.zero? ? 0.0 : passing.fdiv(oracle_valid).round(4)
    {
      "cases" => cases,
      "oracle_valid" => oracle_valid,
      "passing" => passing,
      "pass_rate" => rate,
      "status" => status_line(cases, oracle_valid, passing),
    }
  end

  def status_line(cases, oracle_valid, passing)
    "#{passing}/#{oracle_valid} oracle-valid cases pass; " \
      "#{cases - oracle_valid}/#{cases} cases are rejected by the pinned oracle"
  end

  # Committed rows keep their identity fields (notation, type, provenance);
  # only the measured fields are replaced.
  def fresh_rows(committed)
    require "sirena/notation/plantuml"
    verdict_by_id = verdicts
    committed.map do |row|
      row.merge(measure(row.fetch("type"), verdict_by_id))
    end
  end

  def load_scoreboard
    JSON.parse(File.read(SCOREBOARD_PATH))
  end

  def write_scoreboard(rows)
    tmp_path = "#{SCOREBOARD_PATH}.tmp"
    File.write(tmp_path, "#{JSON.pretty_generate(rows)}\n")
    FileUtils.mv(tmp_path, SCOREBOARD_PATH)
  end

  # One line per measured field that differs, naming the type.
  def drift(committed, fresh)
    fresh.flat_map do |row|
      old = committed.find { |c| c["type"] == row["type"] } || {}
      MEASURED.reject { |key| old[key] == row[key] }
        .map { |key| drift_line(row["type"], key, old[key], row[key]) }
    end
  end

  def drift_line(type, key, committed, measured)
    "#{type}.#{key}: committed #{committed.inspect}, " \
      "measured #{measured.inspect}"
  end

  def check!
    committed = load_scoreboard
    lines = drift(committed, fresh_rows(committed))
    unless lines.empty?
      puts lines
      abort "plantuml:check: FAILED (run `rake plantuml` and commit " \
            "scoreboard/plantuml.json)"
    end
    puts "plantuml:check: clean (passing counts match the committed " \
         "scoreboard)"
  end
end
