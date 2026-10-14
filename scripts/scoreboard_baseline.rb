# frozen_string_literal: true

require_relative "ci_baseline"

# Checks committed ledgers against the CI event baseline. Fresh measurements
# still require corpus:check, conformance:check and layout_parity:check.
module ScoreboardBaseline
  FILES = %w[corpus conformance layout-parity].freeze
  METRICS = %w[worst_e_c worst_e_w worst_e_h worst_e_a worst_analog].freeze

  class Error < StandardError; end

  module_function

  def check(event_name, payload, dir: ".", head: "HEAD")
    baseline = CiBaseline.resolve(event_name, payload, dir: dir, head: head)
    current = snapshot(dir, head)
    errors = []
    errors = regressions(snapshot(dir, baseline.sha), current) if baseline.sha
    { baseline: baseline.sha, mode: baseline.mode, errors: errors }
  end

  def snapshot(dir, ref)
    FILES.to_h do |name|
      path = "scoreboard/#{name}.json"
      out, err, status = CiBaseline.git(dir, "show", "#{ref}:#{path}")
      unless status.success?
        raise Error, "cannot read #{ref}:#{path}: #{err.strip}"
      end

      [name, index(JSON.parse(out), path)]
    end
  rescue JSON::ParserError => e
    raise Error, "malformed scoreboard at #{ref}: #{e.message}"
  end

  def index(rows, path)
    raise Error, "#{path} must be an array" unless rows.is_a?(Array)

    rows.each_with_object({}) do |row, cases|
      id = case_id(row, path)
      raise Error, "#{path} has duplicate case #{id}" if cases.key?(id)

      validate_row(row, path)
      cases[id] = row
    end
  end

  def case_id(row, path)
    id = row.is_a?(Hash) && row["case"]
    return id if id.is_a?(String) && !id.strip.empty?

    raise Error, "#{path} has an empty or invalid case ID"
  end

  def validate_row(row, path)
    case path
    when "scoreboard/corpus.json" then validate_corpus(row)
    when "scoreboard/conformance.json"
      require_value(row["status"], %w[conformant nonconformant], row, "status")
    when "scoreboard/layout-parity.json" then validate_layout(row)
    end
  end

  def validate_corpus(row)
    require_value(row["verdict"], %w[valid invalid artifact], row, "verdict")
    require_value(row["pass"], [true, false], row, "pass")
  end

  def validate_layout(row)
    summary = require_hash(row["summary"], row, "layout summary")
    require_value(summary["hard_failure"], [true, false], row, "hard_failure")
    metrics = require_hash(summary["metrics"], row, "layout metrics")
    METRICS.each { |key| validate_metric(metrics, key, row) }
  end

  def require_hash(value, row, field)
    return value if value.is_a?(Hash)

    raise Error, "#{row['case']} has no #{field}"
  end

  def validate_metric(metrics, key, row)
    value = metrics[key]
    return if metrics.key?(key) && (value.nil? || finite_number?(value))

    raise Error, "#{row['case']} has invalid layout metric #{key}"
  end

  def finite_number?(value)
    value.is_a?(Numeric) && value.finite? && value >= 0
  end

  def require_value(value, allowed, row, field)
    return if allowed.include?(value)

    raise Error, "#{row['case']} has invalid #{field} #{value.inspect}"
  end

  def regressions(previous, current)
    FILES.flat_map do |name|
      previous.fetch(name).flat_map do |id, old|
        row = current.fetch(name)[id]
        if row
          compare(name, id, old, row)
        else
          ["#{name}: deleted case #{id}"]
        end
      end
    end
  end

  def compare(name, id, old, row)
    case name
    when "corpus" then corpus_changes(id, old, row)
    when "conformance"
      return [] unless conformance_regression?(old, row)

      ["conformance: #{id} ceased to be conformant"]
    when "layout-parity" then layout_changes(id, old, row)
    end
  end

  def conformance_regression?(old, row)
    old["status"] == "conformant" && row["status"] != "conformant"
  end

  def corpus_changes(id, old, row)
    errors = []
    if old["verdict"] != row["verdict"]
      errors << "corpus: #{id} verdict changed without " \
                "pinned oracle verification"
    end
    errors << "corpus: #{id} pass regressed" if old["pass"] && !row["pass"]
    errors
  end

  def layout_changes(id, old, row)
    before = old.fetch("summary")
    after = row.fetch("summary")
    errors = []
    if !before["hard_failure"] && after["hard_failure"]
      errors << "layout-parity: #{id} gained a hard failure"
    end
    errors + metric_changes(id, before.fetch("metrics"), after.fetch("metrics"))
  end

  def metric_changes(id, before, after)
    METRICS.filter_map do |key|
      next unless before[key].is_a?(Numeric)
      next if after[key].is_a?(Numeric) && after[key] <= before[key]

      "layout-parity: #{id} metric #{key} increased or disappeared"
    end
  end

  def run(env, dir: ".")
    payload = JSON.parse(File.read(env.fetch("GITHUB_EVENT_PATH")))
    raise Error, "event payload must be an object" unless payload.is_a?(Hash)

    check(env.fetch("GITHUB_EVENT_NAME"), payload, dir: dir)
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    result = ScoreboardBaseline.run(ENV)
    puts JSON.generate(result)
    exit(result.fetch(:errors).empty? ? 0 : 1)
  rescue ScoreboardBaseline::Error, CiBaseline::Error, KeyError,
         Errno::ENOENT, JSON::ParserError => e
    warn "scoreboard_baseline -- #{e.message}"
    exit 1
  end
end
