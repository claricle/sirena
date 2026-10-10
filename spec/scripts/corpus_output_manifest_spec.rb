# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/corpus_output_manifest"

RSpec.describe CorpusOutputManifest do
  let(:directory) { Dir.mktmpdir("corpus-output-manifest") }
  let(:scoreboard_path) { File.join(directory, "corpus-output.json") }
  let(:row) do
    lambda do |name, bytes|
      { "case" => name, "sha256" => Digest::SHA256.hexdigest(bytes) }
    end
  end

  before do
    stub_const("CorpusOutputManifest::SCOREBOARD_PATH", scoreboard_path)
  end

  after { FileUtils.remove_entry(directory) }

  describe ".rows" do
    before do
      allow(described_class).to receive_messages(
        cases: %w[z/2.mmd a/1.mmd invalid/1.mmd broken/1.mmd],
        verdicts: {
          "z/2.mmd" => "valid",
          "a/1.mmd" => "valid",
          "invalid/1.mmd" => "invalid",
          "broken/1.mmd" => "valid",
        },
      )
      allow(described_class).to receive(:render_output) do |name|
        { "z/2.mmd" => "same", "a/1.mmd" => "same" }.fetch(name)
      end
    end

    it "hashes exact bytes without collapsing cases with the same output" do
      expected = [row.call("a/1.mmd", "same"), row.call("z/2.mmd", "same")]

      expect(described_class.rows).to eq(expected)
    end
  end

  describe ".render_output" do
    let(:engine) { instance_double(Sirena::Engine) }

    before do
      corpus_root = File.join(directory, "corpus")
      FileUtils.mkdir_p(File.join(corpus_root, "gantt"))
      File.binwrite(File.join(corpus_root, "gantt", "1.mmd"), "gantt\r\n".b)
      stub_const("CorpusOutputManifest::CORPUS_ROOT", corpus_root)
      allow(Sirena::Engine).to receive(:new).and_return(engine)
    end

    it "renders source bytes with the fixed manifest date" do
      allow(engine).to receive(:render)
        .with("gantt\r\n".b, today: Date.new(2026, 1, 1)).and_return("<svg/>")

      expect(described_class.render_output("gantt/1.mmd")).to eq("<svg/>")
    end
  end

  describe ".diff" do
    let(:committed) do
      [row.call("z/deleted.mmd", "old"), row.call("m/changed.mmd", "old"),
       row.call("b/unchanged.mmd", "same")]
    end
    let(:fresh) do
      [row.call("a/added.mmd", "new"), row.call("m/changed.mmd", "new"),
       row.call("b/unchanged.mmd", "same")]
    end

    it "reports changed bytes" do
      expect(described_class.diff(committed, fresh)[:changed])
        .to eq(["m/changed.mmd"])
    end

    it "reports deletions" do
      expect(described_class.diff(committed, fresh)[:missing])
        .to eq(["z/deleted.mmd"])
    end

    it "reports deterministic additions" do
      expect(described_class.diff(committed, fresh)[:added])
        .to eq(["a/added.mmd"])
    end

    it "rejects duplicate paths instead of choosing one by row order" do
      duplicate = row.call("a/1.mmd", "one")

      expect { described_class.diff([duplicate, duplicate], []) }
        .to raise_error(described_class::ManifestError, /duplicate.*a\/1[.]mmd/)
    end

    it "rejects paths with platform-dependent or relative meanings" do
      ambiguous = ["a/../b.mmd", "/a/b.mmd", "a\\b/1.mmd"]

      ambiguous.each do |name|
        expect { described_class.diff([row.call(name, "one")], []) }
          .to raise_error(described_class::ManifestError, /invalid case path/)
      end
    end

    it "rejects fields outside the case and checksum schema" do
      extra = row.call("a/1.mmd", "one").merge("path" => "b/1.mmd")

      expect { described_class.diff([extra], []) }
        .to raise_error(described_class::ManifestError, /unexpected fields/)
    end
  end

  describe ".record!" do
    let(:fresh) do
      [row.call("z/2.mmd", "two"), row.call("a/1.mmd", "one")]
    end

    before { allow(described_class).to receive(:rows).and_return(fresh) }

    it "reports how many rows it wrote" do
      expect(described_class.record!).to include("wrote 2 output checksums")
    end

    it "writes deterministic JSON ordered by case path" do
      described_class.record!
      recorded = JSON.parse(File.read(scoreboard_path))

      expect(recorded.map { |entry| entry["case"] })
        .to eq(%w[a/1.mmd z/2.mmd])
    end

    it "terminates the JSON document with a newline" do
      described_class.record!

      expect(File.read(scoreboard_path)).to end_with("\n")
    end

    context "when no oracle-valid case renders" do
      let(:previous) { [row.call("a/1.mmd", "one")] }
      let(:fresh) { [] }

      before do
        File.write(scoreboard_path, "#{JSON.pretty_generate(previous)}\n")
      end

      it "refuses to replace the manifest" do
        expect { described_class.record! }
          .to raise_error(described_class::ManifestError, /no output checksums/)
      end

      it "keeps the previous manifest" do
        described_class.record!
      rescue described_class::ManifestError
        nil
      ensure
        expect(JSON.parse(File.read(scoreboard_path))).to eq(previous)
      end
    end
  end

  describe ".check!" do
    let(:committed) do
      [row.call("z/missing.mmd", "old"), row.call("m/changed.mmd", "old")]
    end
    let(:fresh) do
      [row.call("c/added.mmd", "newer"), row.call("a/added.mmd", "new"),
       row.call("m/changed.mmd", "new")]
    end

    before do
      File.write(scoreboard_path, "#{JSON.pretty_generate(committed)}\n")
      allow(described_class).to receive(:rows).and_return(fresh)
    end

    it "reports every drift class and case deterministically" do
      expected = ["CHANGED OUTPUT BYTES:", "  m/changed.mmd",
                  "MISSING OUTPUT:", "  z/missing.mmd", "ADDED OUTPUT:",
                  "  a/added.mmd", "  c/added.mmd"].join("\n")

      expect { described_class.check! }
        .to raise_error(described_class::ManifestError, expected)
    end

    context "when every checksum matches" do
      let(:fresh) { committed.reverse }

      it "reports the exact matching row count" do
        expect(described_class.check!)
          .to eq("corpus-output:check: clean (2 output checksums match)")
      end
    end

    context "with a malformed committed row" do
      before do
        malformed = [{ "case" => "a/1.mmd", "sha256" => "short" }]
        File.write(scoreboard_path, JSON.generate(malformed))
      end

      it "rejects the row instead of hiding it" do
        expect { described_class.check! }
          .to raise_error(described_class::ManifestError, /invalid sha256/)
      end
    end
  end

  describe ".run" do
    before do
      allow(described_class).to receive_messages(
        record!: "recorded", check!: "checked",
      )
    end

    it "dispatches record mode" do
      expect { described_class.run(["--record"]) }
        .to output("recorded\n").to_stdout
    end

    it "dispatches check mode" do
      expect { described_class.run(["--check"]) }
        .to output("checked\n").to_stdout
    end

    it "rejects implicit and misspelled modes" do
      [[], ["--chek"]].each do |argv|
        expect { described_class.run(argv) }
          .to raise_error(described_class::ManifestError, /usage:/)
      end
    end
  end
end
