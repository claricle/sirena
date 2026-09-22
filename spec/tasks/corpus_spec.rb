# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"
require "fileutils"

# lib/tasks/corpus.rake is loaded by the Rakefile via `Dir.glob(...).each { |r|
# load r }`, never `require`d, so it is not on Sirena's own require path.
# `require "rake"` alone puts `task`/`namespace` on the top-level object,
# which is all the DSL calls at the tail of the file need.
load File.expand_path("../../lib/tasks/corpus.rake", __dir__)

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
      "timeout" => Timeout::Error
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

    it "reports the layout stage for a real transform-validity failure" do
      result = described_class.render_case("c4/012_parser_should_parse_a_link_11.mmd")

      expect(result[:pass]).to be(false)
      expect(result[:stage]).to eq("layout")
      expect(result[:exception_class]).to eq("Sirena::Layout::LayoutError")
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
        { "a/1.mmd" => "valid" }
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
        { "verdict" => "artifact", "pass" => true }
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

    it "does not flag a case still failing the same way as either kind of drift" do
      committed = [{ "case" => "a", "pass" => false }]
      fresh = [{ "case" => "a", "pass" => false }]

      diff = described_class.diff_scoreboards(committed, fresh)

      expect(diff[:regressed]).to eq([])
      expect(diff[:unrecorded]).to eq([])
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
