# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"
require "fileutils"

# tasks/corpus.rake is loaded by the Rakefile via `Dir.glob(...).each { |r|
# load r }`, never `require`d, so it is not on Sirena's own require path.
# `require "rake"` alone puts `task`/`namespace` on the top-level object,
# which is all the DSL calls at the tail of the file need.
load File.expand_path("../../tasks/corpus.rake", __dir__)

# Drives Sirena::Corpus.check! without the real corpus or committed
# scoreboard. Include in a spec that defines `committed`.
module CorpusCheckStubs
  def stub_fresh_run(passes)
    results = passes.transform_values { |pass| { pass: pass, stage: "parse", exception_class: "X" } }
    allow(described_class).to receive_messages(
      load_scoreboard: committed, cases: results.keys, run_cases: results,
      verdicts: results.keys.to_h { |path| [path, "valid"] }
    )
  end

  # check! aborts with SystemExit; returns its status, or 0 if it returns.
  def exit_status_of
    yield
    0
  rescue SystemExit => e
    e.status
  end
end

RSpec.describe Sirena::Corpus do
  describe ".types" do
    it "lists the real corpus type directories" do
      expect(described_class.types).to include("pie", "flowchart", "architecture")
    end

    it "excludes non-directory siblings, such as corpus-verdicts.yml" do
      expect(described_class.types).not_to include("corpus-verdicts.yml")
    end
  end

  describe ".cases" do
    it "returns every case under one type, relative to CORPUS_ROOT" do
      pie_cases = described_class.cases("pie")

      expect(pie_cases).not_to be_empty
      expect(pie_cases).to all(start_with("pie/"))
      expect(pie_cases.size).to eq(Dir.glob(File.join(described_class::CORPUS_ROOT, "pie", "*.mmd")).size)
    end

    it "returns every case in the corpus when no type is given" do
      expect(described_class.cases(nil).size).to eq(described_class.types.sum { |t| described_class.cases(t).size })
    end

    it "raises naming the type for an unknown one" do
      expect { described_class.cases("no-such-diagram-type") }
        .to raise_error(/Unknown corpus type.*no-such-diagram-type/)
    end
  end

  describe ".stage_for" do
    {
      "detect" => Sirena::Engine::DiagramTypeError,
      "parse" => Sirena::Parser::ParseError,
      "layout" => Sirena::Layout::LayoutError,
      "render" => Sirena::Renderer::RenderError,
      "timeout" => Timeout::Error,
    }.each do |stage, klass|
      it "classifies #{klass} as #{stage.inspect}" do
        expect(described_class.stage_for(klass.new)).to eq(stage)
      end
    end

    it "classifies anything else as unknown -- the residual PipelineError bucket" do
      expect(described_class.stage_for(RuntimeError.new)).to eq("unknown")
      expect(described_class.stage_for(Sirena::Engine::PipelineError.new)).to eq("unknown")
    end
  end

  describe ".render_case" do
    it "reports pass with no stage or exception_class for a real passing case" do
      result = described_class.render_case("pie/001_rendering_theme_spec_pie_0.mmd")

      expect(result).to eq(pass: true)
    end

    it "reports the detect stage for a real detection failure" do
      result = described_class.render_case("architecture/012_rendering_architecture_spec_architecture_11.mmd")

      expect(result[:pass]).to be(false)
      expect(result[:stage]).to eq("detect")
      expect(result[:exception_class]).to eq("Sirena::Engine::DiagramTypeError")
    end

    it "reports the parse stage for a real parse failure" do
      result = described_class.render_case("architecture/005_rendering_architecture_spec_architecture_4.mmd")

      expect(result[:pass]).to be(false)
      expect(result[:stage]).to eq("parse")
      expect(result[:exception_class]).to eq("Sirena::Parser::ParseError")
    end

    it "reports pass after C4 IR preserves optional link data" do
      result = described_class.render_case("c4/012_parser_should_parse_a_link_11.mmd")

      expect(result).to eq(pass: true)
    end
  end

  describe ".tidy_message" do
    it "drops the object address Parslet embeds, keeping the class" do
      raw = "Syntax error at #<Parslet::Position:0x0000000126150ca8>: Failed"
      tidy = "Syntax error at #<Parslet::Position>: Failed"

      expect(described_class.tidy_message(raw)).to eq(tidy)
    end

    it "leaves a message without an address alone" do
      expect(described_class.tidy_message("plain error")).to eq("plain error")
    end
  end

  describe ".failure_scope" do
    it "reads no filter, or an empty one, as everything" do
      scopes = [nil, ""].map { |filter| described_class.failure_scope(filter) }

      expect(scopes).to eq([nil, nil])
    end

    it "reads valid as the valid-only scope" do
      expect(described_class.failure_scope("valid")).to eq(:valid)
    end

    it "rejects a typo rather than silently listing everything" do
      expect { described_class.failure_scope("vaild") }
        .to raise_error(ArgumentError, /vaild/)
    end
  end

  describe ".run with a type" do
    let(:results) do
      {
        "t/ok.mmd" => { pass: true },
        "t/real.mmd" => { pass: false, stage: "render", exception_class: "E",
                          message: "boom at #<X:0xab12>" },
        "t/junk.mmd" => { pass: false, stage: "parse", exception_class: "E",
                          message: "bad syntax" },
      }
    end
    let(:verdicts) do
      { "t/ok.mmd" => "valid", "t/real.mmd" => "valid",
        "t/junk.mmd" => "artifact" }
    end

    before do
      allow(described_class).to receive_messages(
        cases: results.keys, run_cases: results, verdicts: verdicts,
      )
      allow(described_class).to receive(:write_scoreboard)
    end

    it "prints path, stage, verdict and the tidied error, grouped by stage" do
      grouped = Regexp.new(
        'junk\.mmd\s+parse\s+artifact\s+bad syntax\n' \
        '\s+t/real\.mmd\s+render\s+valid\s+boom at #<X>\n',
      )

      expect { described_class.run("t") }.to output(grouped).to_stdout
    end

    it "does not print passing cases among the failures" do
      expect { described_class.run("t") }.not_to output(/t\/ok\.mmd/).to_stdout
    end

    it "lists evidence-valid failures when the filter is valid" do
      expect { described_class.run("t", "valid") }
        .to output(/t\/real\.mmd/).to_stdout
    end

    it "leaves out artifact failures when the filter is valid" do
      expect { described_class.run("t", "valid") }
        .not_to output(/t\/junk\.mmd/).to_stdout
    end

    it "says none when the filter leaves nothing to list" do
      artifacts = results.keys.to_h { |path| [path, "artifact"] }
      allow(described_class).to receive(:verdicts).and_return(artifacts)

      expect { described_class.run("t", "valid") }
        .to output(/failing \(valid cases only\):\n  none/).to_stdout
    end

    it "never writes the scoreboard for a scoped run" do
      allow(described_class).to receive(:puts)
      described_class.run("t")

      expect(described_class).not_to have_received(:write_scoreboard)
    end
  end

  describe ".rows_for_scoreboard" do
    it "carries the verdict and pass on a passing case, without stage or exception_class" do
      rows = described_class.rows_for_scoreboard(
        { "a/1.mmd" => { pass: true } }, { "a/1.mmd" => "valid" }
      )

      expect(rows).to eq([{ "case" => "a/1.mmd", "verdict" => "valid", "pass" => true }])
    end

    it "carries stage and exception_class on a failing case" do
      rows = described_class.rows_for_scoreboard(
        { "a/1.mmd" => { pass: false, stage: "parse", exception_class: "X", message: "boom" } },
        { "a/1.mmd" => "valid" },
      )

      expect(rows).to eq([{
        "case" => "a/1.mmd", "verdict" => "valid", "pass" => false,
        "stage" => "parse", "exception_class" => "X"
      }])
    end

    it "defaults an unrecorded verdict to unknown rather than raising" do
      rows = described_class.rows_for_scoreboard({ "a/1.mmd" => { pass: true } }, {})

      expect(rows.first["verdict"]).to eq("unknown")
    end

    it "sorts rows by case" do
      rows = described_class.rows_for_scoreboard(
        { "b/1.mmd" => { pass: true }, "a/1.mmd" => { pass: true } }, {}
      )

      expect(rows.map { |r| r["case"] }).to eq(["a/1.mmd", "b/1.mmd"])
    end
  end

  describe ".rate_over_valid" do
    it "counts passes only among verdict == valid rows" do
      rows = [
        { "verdict" => "valid", "pass" => true },
        { "verdict" => "valid", "pass" => false },
        { "verdict" => "invalid", "pass" => false },
        { "verdict" => "artifact", "pass" => true },
      ]

      expect(described_class.rate_over_valid(rows)).to eq([1, 2])
    end
  end

  describe ".diff_scoreboards" do
    # The pure regression/improvement comparison corpus:check gates on,
    # tested with synthetic rows so it needs neither the real corpus nor
    # a real committed file.
    it "flags a case that passed before and fails now as regressed" do
      committed = [{ "case" => "a", "pass" => true }]
      fresh = [{ "case" => "a", "pass" => false }]

      diff = described_class.diff_scoreboards(committed, fresh)

      expect(diff[:regressed]).to eq(["a"])
      expect(diff[:unrecorded]).to eq([])
    end

    it "flags a case that failed before and passes now as unrecorded" do
      committed = [{ "case" => "a", "pass" => false }]
      fresh = [{ "case" => "a", "pass" => true }]

      diff = described_class.diff_scoreboards(committed, fresh)

      expect(diff[:unrecorded]).to eq(["a"])
      expect(diff[:regressed]).to eq([])
    end

    it "flags a case missing from the committed file entirely, if it now passes" do
      committed = []
      fresh = [{ "case" => "a", "pass" => true }]

      diff = described_class.diff_scoreboards(committed, fresh)

      expect(diff[:unrecorded]).to eq(["a"])
    end

    it "flags a case that passed before and is now entirely missing from the fresh run as regressed" do
      # A case can vanish from the fresh run by deletion (or rename) under
      # spec/mermaid, not just by failing outright. Iterating fresh_pass
      # alone (as the first version of this method did) misses this
      # entirely: a deleted passing case produced an empty diff on both
      # sides, silently defeating the whole ratchet.
      committed = [{ "case" => "a", "pass" => true }]
      fresh = []

      diff = described_class.diff_scoreboards(committed, fresh)

      expect(diff[:regressed]).to eq(["a"])
      expect(diff[:unrecorded]).to eq([])
    end

    it "does not flag a case that failed before and is now entirely missing from the fresh run" do
      committed = [{ "case" => "a", "pass" => false }]
      fresh = []

      diff = described_class.diff_scoreboards(committed, fresh)

      expect(diff[:regressed]).to eq([])
      expect(diff[:unrecorded]).to eq([])
    end

    it "reports nothing when every case matches the committed file" do
      committed = [{ "case" => "a", "pass" => true }, { "case" => "b", "pass" => false }]
      fresh = [{ "case" => "a", "pass" => true }, { "case" => "b", "pass" => false }]

      diff = described_class.diff_scoreboards(committed, fresh)

      expect(diff[:regressed]).to eq([])
      expect(diff[:unrecorded]).to eq([])
    end

    it "flags a case whose verdict changed though its pass flag did not" do
      committed = [{ "case" => "a", "verdict" => "unknown", "pass" => false }]
      fresh = [{ "case" => "a", "verdict" => "valid", "pass" => false }]

      expect(described_class.diff_scoreboards(committed, fresh))
        .to eq(regressed: [], unrecorded: [], reclassified: ["a"])
    end

    it "lists reclassified cases in sorted order" do
      committed = %w[b a].map { |c| { "case" => c, "verdict" => "unknown" } }
      fresh = %w[b a].map { |c| { "case" => c, "verdict" => "valid" } }

      expect(described_class.diff_scoreboards(committed, fresh))
        .to include(reclassified: %w[a b])
    end

    it "does not call a case new to the file reclassified" do
      committed = [{ "case" => "a", "verdict" => "valid", "pass" => true }]
      fresh = [{ "case" => "a", "verdict" => "valid", "pass" => true },
               { "case" => "b", "verdict" => "valid", "pass" => false }]

      expect(described_class.diff_scoreboards(committed, fresh))
        .to include(reclassified: [])
    end

    it "does not flag a case still failing the same way as either kind of drift" do
      committed = [{ "case" => "a", "pass" => false }]
      fresh = [{ "case" => "a", "pass" => false }]

      diff = described_class.diff_scoreboards(committed, fresh)

      expect(diff[:regressed]).to eq([])
      expect(diff[:unrecorded]).to eq([])
    end
  end

  describe ".fail_on_drift!" do
    let(:recorded) do
      verdicts = %w[valid unknown valid]
      committed.zip(verdicts).map { |row, v| row.merge("verdict" => v) }
    end
    let(:all_valid) { committed.map { |row| row.merge("verdict" => "valid") } }
    let(:verdict_changed_report) do
      "VERDICT CHANGED (run `rake corpus` and commit " \
        "scoreboard/corpus.json):\n  b\n"
    end

    # "c" stays passing in both committed and fresh in every example below --
    # it never regresses and is always already recorded, so it must never
    # appear in either printed block. Asserting exact stdout (not a loose
    # substring) is what proves that: a `fail_on_drift!` that printed every
    # committed case instead of just the drifted ones would still satisfy a
    # regex like /REGRESSED.*\n  a\n/, but not an exact match against a
    # block containing only "a".
    let(:committed) do
      [
        { "case" => "a", "pass" => true },
        { "case" => "b", "pass" => false },
        { "case" => "c", "pass" => true },
      ]
    end

    it "exits non-zero and names only the case that regressed" do
      fresh = [
        { "case" => "a", "pass" => false },
        { "case" => "b", "pass" => false },
        { "case" => "c", "pass" => true },
      ]

      expect { described_class.fail_on_drift!(committed, fresh) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output("REGRESSED (passed in the committed scoreboard, fails now):\n  a\n").to_stdout
    end

    it "exits non-zero and names only the case that improved without being recorded" do
      fresh = [
        { "case" => "a", "pass" => true },
        { "case" => "b", "pass" => true },
        { "case" => "c", "pass" => true },
      ]

      expect { described_class.fail_on_drift!(committed, fresh) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output("IMPROVED BUT NOT RECORDED (run `rake corpus` and commit scoreboard/corpus.json):\n  b\n").to_stdout
    end

    it "exits non-zero and names only the case whose verdict changed" do
      expect { described_class.fail_on_drift!(recorded, all_valid) }
        .to raise_error(SystemExit).and output(verdict_changed_report).to_stdout
    end

    it "returns without exiting when the fresh run matches" do
      expect { described_class.fail_on_drift!(committed, committed) }.to output(/corpus:check: clean/).to_stdout
    end
  end

  describe ".check!" do
    # The abort path corpus:check gates CI on, driven with stubbed renders
    # so it needs neither the real corpus nor the committed scoreboard.
    let(:committed) { [{ "case" => "a/1.mmd", "verdict" => "valid", "pass" => true }] }

    include CorpusCheckStubs

    it "exits non-zero and names a case that passed in the scoreboard and fails now" do
      stub_fresh_run("a/1.mmd" => false)

      status = nil
      expect { status = exit_status_of { described_class.check! } }
        .to output(%r{REGRESSED.*\n\s+a/1\.mmd}).to_stdout
      expect(status).to eq(1)
    end

    it "exits non-zero and names a passing case the scoreboard does not record" do
      stub_fresh_run("a/1.mmd" => true, "a/2.mmd" => true)

      status = nil
      expect { status = exit_status_of { described_class.check! } }
        .to output(%r{IMPROVED BUT NOT RECORDED.*\n\s+a/2\.mmd}).to_stdout
      expect(status).to eq(1)
    end

    it "exits non-zero when the committed scoreboard is missing or empty" do
      # A fresh run of nothing diffs clean against nothing, so only the
      # explicit empty-file abort can make this exit non-zero.
      allow(described_class).to receive_messages(load_scoreboard: [], cases: [], run_cases: {}, verdicts: {})

      expect(exit_status_of { described_class.check! }).to eq(1)
    end

    it "returns normally when fresh results match the committed scoreboard" do
      stub_fresh_run("a/1.mmd" => true)

      expect { described_class.check! }.to output(/corpus:check: clean \(1 cases/).to_stdout
    end
  end

  describe "a seeded detection failure" do
    let(:root) { Dir.mktmpdir }

    before do
      FileUtils.mkdir_p(File.join(root, "seeded"))
      File.write(File.join(root, "seeded", "1.mmd"), "notADiagramType\n  A --> B\n")
      stub_const("Sirena::Corpus::CORPUS_ROOT", root)
    end

    after { FileUtils.remove_entry(root) }

    it "lands in the scoreboard row with stage detect" do
      rows = described_class.rows_for_scoreboard(described_class.run_cases(["seeded/1.mmd"]), {})

      expect(rows).to eq([{
        "case" => "seeded/1.mmd", "verdict" => "unknown", "pass" => false,
        "stage" => "detect", "exception_class" => "Sirena::Engine::DiagramTypeError"
      }])
    end
  end
end
