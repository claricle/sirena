# frozen_string_literal: true

require "rake"
require "spec_helper"
require_relative "../../tasks/support/layout_parity"

module LayoutParity
end

RSpec.describe LayoutParity do
  include UnshardedRakefile

  let(:scoreboard) { Sirena::LayoutParityScoreboard }
  let(:directory) { Dir.mktmpdir }
  let(:path) { File.join(directory, "layout-parity.json") }

  after { FileUtils.remove_entry(directory) }

  it "atomically records the complete fresh ledger" do
    fresh = [row("b", hard_failure: true), row("a")]
    expect(record_summary(fresh))
      .to eq(["2 cases, 1 hard failures", fresh, []])
  end

  it "closes the temporary file before replacing the scoreboard" do
    calls = observe_temporary_replacement
    scoreboard.record!(fresh: [row("a")], path: path)
    expect(calls).to eq(%i[closed renamed])
  end

  it "keeps the committed baseline intact when replacement fails" do
    File.write(path, "old baseline\n")
    allow(File).to receive(:rename).and_raise(Errno::EIO)
    expect(failed_record_summary)
      .to eq([Errno::EIO, "old baseline\n", []])
  end

  it "checks an identical baseline without writing it" do
    fresh = [row("a")]
    File.write(path, JSON.generate(fresh))
    allow(scoreboard).to receive(:write_scoreboard)
    scoreboard.check!(fresh: fresh, path: path)
    expect(scoreboard).not_to have_received(:write_scoreboard)
  end

  it "reports missing, new, stale, regressed, and improved evidence" do
    write_drift_baseline
    expect(drift_message).to include(*expected_drift_messages)
  end

  it "refuses to replace the baseline with an empty measurement" do
    File.write(path, JSON.generate([row("a")]))
    expect(empty_record_summary)
      .to eq(["no parity cases measured", [row("a")]])
  end

  it "rejects a malformed committed row before comparison" do
    File.write(path, JSON.generate([{}]))
    expect { scoreboard.check!(fresh: [row("a")], path: path) }
      .to raise_error(scoreboard::DriftError, /invalid parity rows/)
  end

  it "wires the check into the default task used by both CI lanes" do
    with_rake_application do
      load_unsharded_rakefile
      expect(Rake::Task[:default].prerequisites)
        .to include("layout_parity:check")
    end
  end

  it "makes the record and check tasks executable" do
    expect { invoke_rake_tasks }.to output("recorded\nchecked\n").to_stdout
  end

  def record_summary(fresh)
    message = scoreboard.record!(fresh: fresh, path: path)
    [message[/\d+ cases, \d+ hard failures/],
     JSON.parse(File.read(path)), temporary_files]
  end

  def observe_temporary_replacement
    calls = []
    temporary = instance_spy(Tempfile, path: "temporary")
    allow(Tempfile).to receive(:create).and_yield(temporary)
    allow(temporary).to receive(:close) { calls << :closed }
    allow(File).to receive(:rename) { calls << :renamed }
    calls
  end

  def failed_record_summary
    scoreboard.record!(fresh: [row("a")], path: path)
  rescue Errno::EIO => e
    [e.class, File.read(path), temporary_files]
  end

  def temporary_files
    Dir.glob("#{path}.*.tmp")
  end

  def write_drift_baseline
    File.write(path, JSON.generate(committed_drift_rows))
  end

  def committed_drift_rows
    [row("missing"), row("changed", center: 0.2),
     row("improved", center: 0.4, hard_failure: true),
     row("stale", reference: "old.svg")]
  end

  def fresh_drift_rows
    [row("new"), row("changed", center: 0.3),
     row("improved", center: 0.1),
     row("stale", reference: "new.svg")]
  end

  def drift_message
    scoreboard.check!(fresh: fresh_drift_rows, path: path)
  rescue scoreboard::DriftError => e
    e.message
  end

  def expected_drift_messages
    ["MISSING FROM FRESH MEASUREMENT:\n  missing",
     "NEW CASES NOT RECORDED:\n  new",
     "REGRESSIONS:\n  changed worst_e_c: 0.2 -> 0.3",
     "IMPROVEMENTS NOT RECORDED:",
     "improved hard_failure: true -> false",
     "STALE EVIDENCE:",
     "\n  stale",
     "run `bundle exec rake layout_parity`"]
  end

  def empty_record_summary
    scoreboard.record!(fresh: [], path: path)
  rescue scoreboard::DriftError => e
    [e.message[/no parity cases measured/], JSON.parse(File.read(path))]
  end

  def invoke_rake_tasks
    with_rake_application do
      load File.expand_path("../../tasks/layout_parity.rake", __dir__)
      allow(scoreboard).to receive_messages(record!: "recorded",
                                            check!: "checked")
      Rake::Task[:layout_parity].invoke
      Rake::Task["layout_parity:check"].invoke
    end
  end

  def row(case_id, center: nil, hard_failure: false, reference: "ref.svg")
    metrics = SpecSupport::LayoutParity::CaseLedger::METRICS.to_h do |metric|
      [metric, metric == "worst_e_c" ? center : nil]
    end
    { "case" => case_id, "reference" => reference,
      "summary" => { "hard_failure" => hard_failure,
                     "metrics" => metrics } }
  end

  def with_rake_application
    original = Rake.application
    Rake.application = Rake::Application.new
    yield
  ensure
    Rake.application = original
  end
end
