# frozen_string_literal: true

require "fileutils"
require "json"
require "timeout"
require "tmpdir"
require "yaml"
require_relative "hardened_mmdc"
require_relative "mmdc_oracle"

# Settles corpus cases that no sidecar, reference or twin speaks for, by
# asking the local mmdc and committing the answer to
# spec/mermaid/oracle-verdicts.yml, so scripts/corpus_verdicts.rb can classify
# them without mmdc installed.
#
# Only a mermaid verdict is recorded. A browser that will not start, a hung
# page or an unrecognisable failure raises InfrastructureError and the whole
# refresh writes nothing: a broken tool must not be able to declare the corpus
# invalid.
module CorpusOracle
  PATH = File.expand_path("../spec/mermaid/oracle-verdicts.yml", __dir__)

  # The only mmdc these verdicts are valid for. The toolchain is not pinned
  # yet (TODO.foundation/02a), so a different CLI answers a different question.
  EXPECTED_CLI = "11.12.0"

  class InfrastructureError < StandardError; end

  # A thrown mermaid diagnostic names its class on its first line
  # ("Error: ...", "TypeError: ...", "UnknownDiagramError: ...") and its stack
  # runs through the mermaid bundle. A Puppeteer or Chromium failure ("Error:
  # Browser was not found ...", "Target closed") has the same first line and
  # no such frame, so the frame is what tells a refusal from a crash.
  DIAGNOSTIC_HEAD = /\A\w*Error: /
  MERMAID_FRAME = %r{(?:\A|[/\\])mermaid\.js:\d+}

  module_function

  # digest => row, or {} when no refresh has been committed.
  def load_rows(path = PATH)
    return {} unless File.exist?(path)

    rows = YAML.load_file(path).fetch("cases")
    rows.to_h { |row| [row.fetch("sha256"), row] }
  end

  # Returns [verdict, evidence] with verdict "valid" or "invalid".
  def row_verdict(row)
    case row.fetch("verdict")
    when "accepts" then ["valid", evidence("renders it")]
    when "rejects" then ["invalid", evidence("rejects it: #{row['reason']}")]
    else raise ArgumentError, "unrecognised verdict #{row['verdict'].inspect}"
    end
  end

  def evidence(what)
    "mmdc #{EXPECTED_CLI} #{what} (oracle-verdicts.yml)"
  end

  # Runs one source through mmdc. Returns ["accepts", nil] or
  # ["rejects", reason]; raises InfrastructureError for anything else.
  #
  # A rejection must reproduce: the same diagnostic head on a second run.
  # mmdc funnels Puppeteer and Chromium crashes through the same exit status
  # as a refusal, so one failed run proves nothing.
  def judge(path, &runner)
    killed = []
    watched = watching(runner, killed)
    first = MmdcOracle.verdict(path, &watched)
    return ["accepts", nil] if first.verdict == :accepts

    second = MmdcOracle.verdict(path, &watched)
    refuse!(path, "mmdc was killed before it answered") if killed.any?
    reason = reproduced_reason(path, first, second)
    ["rejects", reason.empty? ? "mermaid error page" : reason[0, 120]]
  end

  # A run mmdc never finished (nil status) proves nothing about the source,
  # whatever it printed before it was killed.
  def watching(runner, killed)
    lambda do |input, output|
      runner.call(input, output).tap do |status, _|
        killed << input if status.nil?
      end
    end
  end

  def reproduced_reason(path, first, second)
    reason = head(first)
    same = first.verdict == second.verdict && reason == head(second)
    refuse!(path, "failed differently on a second run") unless same
    refuse!(path, "not a mermaid diagnostic: #{reason.inspect}") unless
      [first, second].all? { |run| diagnostic?(run, reason) }
    reason
  end

  # A rejection with no stderr at all is mermaid's own error page, which
  # MmdcOracle only reports for a well-formed SVG.
  def diagnostic?(result, reason)
    return result.verdict == :rejects if reason.empty?

    reason.match?(DIAGNOSTIC_HEAD) && stack(result).match?(MERMAID_FRAME)
  end

  def refuse!(path, why)
    raise InfrastructureError, "#{path}: #{why}"
  end

  # First stderr line that is not mmdc's progress banner.
  def head(result)
    lines = stack(result).lines.map(&:strip)
    lines.find { |l| !l.empty? && !l.start_with?("Generating single") }.to_s
  end

  # mmdc's stderr as readable text: HardenedMmdc hands it back binary-tagged,
  # and FORCE_COLOR wraps lines in ANSI colour codes.
  def stack(result)
    text = result.diagnostic.dup.force_encoding(Encoding::UTF_8).scrub
    text.gsub(/\e\[[\d;]*m/, "")
  end

  def canary!(&)
    Dir.mktmpdir("oracle-canary") do |dir|
      path = File.join(dir, "canary.mmd")
      File.write(path, MmdcOracle::CANARY_SOURCE)
      return if MmdcOracle.verdict(path, &).verdict == :accepts
    end
    raise InfrastructureError, "mmdc failed its known-valid canary"
  end

  # entries: [{path:, digest:, case:}, ...]; one judgement per distinct source.
  def refresh(entries, provenance:, path: PATH, &)
    canary!(&)
    groups = entries.group_by { |e| e[:digest] }.values
    groups = groups.sort_by { |group| group.map { |e| e[:case] }.min }
    rows = groups.map { |group| row_for(group, &) }
    canary!(&)
    write(path, provenance, rows)
    rows
  end

  def row_for(group, &)
    verdict, reason = judge(group.first.fetch(:path), &)
    { "sha256" => group.first.fetch(:digest), "verdict" => verdict,
      "reason" => reason, "cases" => group.map { |e| e[:case] }.sort }.compact
  end

  def write(path, provenance, rows)
    tmp = "#{path}.#{Process.pid}.tmp"
    File.write(tmp, { "provenance" => provenance, "cases" => rows }.to_yaml)
    File.rename(tmp, path)
  ensure
    FileUtils.rm_f(tmp)
  end

  def provenance
    cli = cli_version
    unless cli == EXPECTED_CLI
      found = cli.empty? ? "missing or not answering" : cli
      raise InfrastructureError, "mmdc is #{found}, not #{EXPECTED_CLI}"
    end

    { "mmdc" => cli, "mermaid" => mermaid_version,
      "note" => "toolchain not pinned (TODO.foundation/02a)" }
  end

  def cli_version
    HardenedMmdc.capture(["mmdc", "--version"], 120).strip
  rescue SystemCallError, Timeout::Error
    ""
  end

  # mermaid-cli keeps its own copy of mermaid next to its sources.
  def mermaid_version
    bin = mmdc_on_path
    return "unknown" unless bin

    manifest = File.join(File.dirname(File.realpath(bin)), "..",
                         "node_modules", "mermaid", "package.json")
    return "unknown" unless File.exist?(manifest)

    JSON.parse(File.read(manifest))["version"]
  end

  def mmdc_on_path
    dirs = ENV.fetch("PATH").split(File::PATH_SEPARATOR)
    dirs.map { |dir| File.join(dir, "mmdc") }.find { |f| File.executable?(f) }
  end
end
