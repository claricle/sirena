# frozen_string_literal: true

require "bundler/setup"
require "date"
require "digest"
require "fileutils"
require "json"
require "timeout"
require "yaml"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "sirena"

# Records the exact bytes Sirena emits for every oracle-valid Mermaid case
# that currently renders. The case path is part of every row so equal output
# bytes cannot collapse distinct corpus cases.
module CorpusOutputManifest
  class ManifestError < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  CORPUS_ROOT = File.join(ROOT, "spec", "mermaid")
  VERDICTS_PATH = File.join(CORPUS_ROOT, "corpus-verdicts.yml")
  SCOREBOARD_PATH = File.join(ROOT, "scoreboard", "corpus-output.json")
  CASE_TIMEOUT = 10
  TODAY = Date.new(2026, 1, 1)
  SHA256 = /\A[0-9a-f]{64}\z/
  CASE_PATH = /\A[^\/\\\x00-\x1F]+\/[^\/\\\x00-\x1F]+[.]mmd\z/
  AMBIGUOUS_PATH_PARTS = %w[. ..].freeze

  module_function

  def cases
    Dir.glob(File.join(CORPUS_ROOT, "*", "*.mmd")).map do |path|
      path.delete_prefix("#{CORPUS_ROOT}/")
    end
  end

  def verdicts
    rows = YAML.load_file(VERDICTS_PATH)
    unless rows.is_a?(Array) && rows.all?(Hash)
      raise ManifestError, "#{VERDICTS_PATH} is not a list of verdict rows"
    end

    index_verdicts(rows)
  end

  def index_verdicts(rows)
    duplicates = duplicate_values(rows, "case")
    unless duplicates.empty?
      raise ManifestError,
            "duplicate verdict case path: #{duplicates.join(', ')}"
    end

    rows.to_h { |row| [row["case"], row["verdict"]] }
  end

  def render_output(relative_path)
    source = File.binread(File.join(CORPUS_ROOT, relative_path))
    Timeout.timeout(CASE_TIMEOUT) do
      Sirena::Engine.new.render(source, today: TODAY)
    end
  end

  def output_for(relative_path)
    render_output(relative_path)
  rescue StandardError
    nil
  end

  def rows
    verdict_by_case = verdicts
    cases.filter_map do |relative_path|
      output_row(relative_path, verdict_by_case[relative_path])
    end.sort_by { |row| row.fetch("case") }
  end

  def output_row(relative_path, verdict)
    return unless verdict == "valid"

    output = output_for(relative_path)
    return unless output.is_a?(String)

    { "case" => relative_path,
      "sha256" => Digest::SHA256.hexdigest(output.b) }
  end

  def normalize_rows(rows)
    unless rows.is_a?(Array) && rows.all?(Hash)
      raise ManifestError, "manifest is not a list of rows"
    end

    rows.each { |row| validate_row(row) }
    reject_duplicate_paths(rows)
    rows.sort_by { |row| row.fetch("case") }
  end

  def validate_row(row)
    unless row.keys.sort == %w[case sha256]
      raise ManifestError, "manifest row has unexpected fields: #{row.inspect}"
    end

    validate_case_path(row["case"])
    validate_digest(row["case"], row["sha256"])
  end

  def validate_case_path(relative_path)
    valid = relative_path.is_a?(String) && CASE_PATH.match?(relative_path)
    valid &&= !relative_path.split("/").intersect?(AMBIGUOUS_PATH_PARTS)
    return if valid

    raise ManifestError, "invalid case path: #{relative_path.inspect}"
  end

  def validate_digest(relative_path, digest)
    return if digest.is_a?(String) && SHA256.match?(digest)

    raise ManifestError,
          "invalid sha256 for #{relative_path}: #{digest.inspect}"
  end

  def reject_duplicate_paths(rows)
    duplicates = duplicate_values(rows, "case")
    return if duplicates.empty?

    raise ManifestError,
          "duplicate case path in manifest: #{duplicates.join(', ')}"
  end

  def duplicate_values(rows, key)
    rows.group_by { |row| row[key] }
      .select { |_, matches| matches.size > 1 }.keys.sort
  end

  def index(rows)
    normalize_rows(rows).to_h { |row| [row.fetch("case"), row] }
  end

  def diff(committed, fresh)
    before = index(committed)
    after = index(fresh)
    {
      changed: changed_paths(before, after),
      missing: (before.keys - after.keys).sort,
      added: (after.keys - before.keys).sort,
    }
  end

  def changed_paths(before, after)
    (before.keys & after.keys).reject do |name|
      before.fetch(name).fetch("sha256") == after.fetch(name).fetch("sha256")
    end.sort
  end

  def write_manifest(fresh)
    normalized = normalize_rows(fresh)
    FileUtils.mkdir_p(File.dirname(SCOREBOARD_PATH))
    temporary = "#{SCOREBOARD_PATH}.#{Process.pid}.tmp"
    File.write(temporary, "#{JSON.pretty_generate(normalized)}\n")
    File.rename(temporary, SCOREBOARD_PATH)
  ensure
    FileUtils.rm_f(temporary) if temporary
  end

  def load_manifest
    unless File.file?(SCOREBOARD_PATH)
      raise ManifestError,
            "#{SCOREBOARD_PATH} is missing; run with --record first"
    end

    normalize_rows(JSON.parse(File.read(SCOREBOARD_PATH)))
  rescue JSON::ParserError => e
    raise ManifestError, "#{SCOREBOARD_PATH} is not valid JSON: #{e.message}"
  end

  def record!
    fresh = rows
    if fresh.empty?
      raise ManifestError,
            "no output checksums measured; keeping #{SCOREBOARD_PATH}"
    end

    write_manifest(fresh)
    "corpus-output:record: wrote #{fresh.size} output checksums to " \
      "#{SCOREBOARD_PATH}"
  end

  def check!
    committed = load_manifest
    fresh = rows
    drift = diff(committed, fresh)
    raise ManifestError, drift_report(drift) if drift.values.any?(&:any?)

    "corpus-output:check: clean (#{fresh.size} output checksums match)"
  end

  HEADINGS = {
    changed: "CHANGED OUTPUT BYTES:",
    missing: "MISSING OUTPUT:",
    added: "ADDED OUTPUT:",
  }.freeze

  def drift_report(drift)
    HEADINGS.flat_map do |kind, heading|
      next [] if drift.fetch(kind).empty?

      [heading, *drift.fetch(kind).map { |name| "  #{name}" }]
    end.join("\n")
  end

  def run(argv)
    puts command(argv)
  end

  def command(argv)
    return record! if argv == ["--record"]
    return check! if argv == ["--check"]

    raise ManifestError, "usage: corpus_output_manifest.rb --record|--check"
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    CorpusOutputManifest.run(ARGV)
  rescue CorpusOutputManifest::ManifestError => e
    warn e.message
    exit 1
  end
end
