# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../../scripts/scoreboard_baseline"

RSpec.describe ScoreboardBaseline, :aggregate_failures do
  let(:root) { Dir.mktmpdir("scoreboard-baseline") }
  let(:repo) { SeededScoreboardRepo.new(root) }
  let(:data) { repo.ledgers }

  after { FileUtils.remove_entry(root) }

  %w[pull_request push merge_group workflow_dispatch].each do |event|
    context "with a #{event} Git history" do
      before { repo.metrics(data)["worst_e_c"] = 0.01 }

      it "accepts recorded improvements and additional cases" do
        out, err, status = repo.recorded_improvement(event)

        expect(status.exitstatus).to eq(0), err
        expect(JSON.parse(out)).to include("baseline" => repo.base,
                                           "errors" => [])
      end

      it "rejects one regression alongside an improvement" do
        data.fetch("corpus").first["pass"] = false
        out, _err, status = repo.record_and_run(data, event, repo.event(event))

        expect(status.exitstatus).to eq(1)
        expect(JSON.parse(out).fetch("errors"))
          .to include(/a.mmd pass regressed/)
      end
    end
  end

  context "with a fork PR regression" do
    before { data.fetch("conformance").first["status"] = "nonconformant" }

    let(:result) do
      payload = repo.event("pull_request", fork: true)
      repo.record_and_run(data, "pull_request", payload)
    end

    it "uses the fork PR merge-base and rejects its regression" do
      expect(result.last.exitstatus).to eq(1)
      expect(JSON.parse(result.first)).to include("baseline" => repo.base,
                                                  "mode" => "fork_pull_request")
      expect(JSON.parse(result.first).fetch("errors"))
        .to include(/ceased to be conformant/)
    end
  end

  %w[corpus conformance layout-parity].each do |ledger|
    it "rejects deletion from #{ledger} even when another case replaces it" do
      data.fetch(ledger).first["case"] = "flowchart/replacement.mmd"
      out, _err, status = repo.record_and_run(data, "push", repo.event("push"))

      expect(status.exitstatus).to eq(1)
      expect(JSON.parse(out).fetch("errors"))
        .to include("#{ledger}: deleted case flowchart/a.mmd")
    end
  end

  it "rejects unwitnessed oracle verdict changes" do
    data.fetch("corpus").first["verdict"] = "invalid"
    out, _err, status = repo.record_and_run(data, "push", repo.event("push"))

    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(out).fetch("errors")).to include(/verdict changed/)
  end

  it "rejects a newly recorded layout hard failure" do
    data.fetch("layout-parity").first.fetch("summary")["hard_failure"] = true
    out, _err, status = repo.record_and_run(data, "merge_group",
                                            repo.event("merge_group"))

    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(out).fetch("errors")).to include(/gained a hard failure/)
  end

  described_class::METRICS.each do |metric|
    it "rejects a numeric increase in #{metric}" do
      out, _err, status = repo.metric_increase(metric)

      expect(status.exitstatus).to eq(1)
      expect(JSON.parse(out).fetch("errors"))
        .to include(/metric #{metric} increased/)
    end
  end

  it "rejects loss of a previously numeric metric" do
    repo.metrics(data)["worst_e_c"] = nil
    out, _err, status = repo.record_and_run(data, "push", repo.event("push"))

    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(out).fetch("errors"))
      .to include(/metric worst_e_c increased or disappeared/)
  end

  %w[schedule workflow_dispatch].each do |event|
    it "validates HEAD without inventing a #{event} baseline" do
      repo.commit
      out, err, status = repo.run_cli(event, {})

      expect(status.exitstatus).to eq(0), err
      expect(JSON.parse(out)).to include("baseline" => nil, "mode" => event,
                                         "errors" => [])
    end

    it "fails closed on duplicate IDs in consistency-only #{event}" do
      data.fetch("corpus") << data.fetch("corpus").first.dup
      _out, err, status = repo.record_and_run(data, event, {})

      expect(status.exitstatus).to eq(1)
      expect(err).to include("duplicate case")
    end
  end

  [nil, "", "   ", 1].each do |id|
    it "rejects invalid case ID #{id.inspect}" do
      data.fetch("corpus").first["case"] = id
      _out, err, status = repo.record_and_run(data, "schedule", {})

      expect(status.exitstatus).to eq(1)
      expect(err).to include("invalid case ID")
    end
  end

  context "with malformed row fields" do
    [
      ["corpus", "pass", "true"],
      ["corpus", "verdict", "unknown"],
      ["conformance", "status", nil],
      ["layout-parity", "summary", nil],
    ].each do |ledger, field, value|
      it "rejects invalid #{ledger} #{field}" do
        data.fetch(ledger).first[field] = value
        _out, err, status = repo.record_and_run(data, "schedule", {})

        expect(status.exitstatus).to eq(1)
        expect(err).to include("scoreboard_baseline --")
      end
    end
  end

  it "fails closed on a missing committed HEAD ledger" do
    repo.git("rm", "scoreboard/conformance.json")
    repo.commit
    _out, err, status = repo.run_cli("schedule", {})

    expect(status.exitstatus).to eq(1)
    expect(err).to include("cannot read HEAD:scoreboard/conformance.json")
  end

  it "fails closed on a malformed baseline ledger" do
    _out, err, status = repo.malformed_baseline

    expect(status.exitstatus).to eq(1)
    expect(err).to include("must be an array")
  end

  it "fails closed on malformed committed JSON" do
    File.write(File.join(repo.dir, "scoreboard", "corpus.json"), "{")
    repo.commit
    _out, err, status = repo.run_cli("schedule", {})

    expect(status.exitstatus).to eq(1)
    expect(err).to include("malformed scoreboard")
  end

  it "reads committed HEAD rather than uncommitted replacements" do
    repo.commit
    repo.write("corpus" => [])
    out, err, status = repo.run_cli("push", repo.event("push"))

    expect(status.exitstatus).to eq(0), err
    expect(JSON.parse(out).fetch("errors")).to eq([])
  end
end
