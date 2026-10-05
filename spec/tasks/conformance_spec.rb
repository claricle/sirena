# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"
require "fileutils"
require_relative "../../tasks/support/conformance"

module ConformanceSpecRows
  def row(name, status)
    { "case" => name, "status" => status }
  end
end

RSpec.describe Sirena::Conformance do
  include ConformanceSpecRows

  let(:valid_svg) do
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="1" height="1"/></svg>'
  end
  let(:invalid_svg) do
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><script>x</script></svg>'
  end
  let(:malformed_svg) do
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><text>a & b</text></svg>'
  end

  describe ".status_for" do
    it "calls a well-formed document the profile accepts conformant" do
      expect(described_class.status_for(valid_svg)).to eq("conformant")
    end

    it "calls a well-formed document the profile rejects nonconformant" do
      expect(described_class.status_for(invalid_svg)).to eq("nonconformant")
    end

    it "calls a document that is not well-formed XML nonconformant" do
      expect(described_class.status_for(malformed_svg)).to eq("nonconformant")
    end

    it "calls a well-formed fragment with no svg root nonconformant" do
      expect(described_class.status_for("<rect/>")).to eq("nonconformant")
    end

    it "calls what Sirena renders for a real case conformant" do
      svg = described_class.render("pie/001_rendering_theme_spec_pie_0.mmd")

      expect(described_class.status_for(svg)).to eq("conformant")
    end
  end

  describe ".render and .cases" do
    let(:root) { Dir.mktmpdir }

    before do
      FileUtils.mkdir_p(File.join(root, "pie"))
      File.write(File.join(root, "pie", "b.mmd"), "pie\n  \"a\" : 1\n")
      File.write(File.join(root, "pie", "a.mmd"), "notADiagramType\n  A --> B\n")
      stub_const("Sirena::Conformance::CORPUS_ROOT", root)
    end

    after { FileUtils.remove_entry(root) }

    it "lists cases relative to the corpus root" do
      expect(described_class.cases).to eq(["pie/a.mmd", "pie/b.mmd"])
    end

    it "returns nil for a case that does not render" do
      expect(described_class.render("pie/a.mmd")).to be_nil
    end

    it "returns the document for a case that renders" do
      expect(described_class.render("pie/b.mmd")).to start_with("<svg")
    end

    it "gives a row only to the cases that render" do
      expect(described_class.rows).to eq([row("pie/b.mmd", "conformant")])
    end

    it "returns nil for a case that outlives the time limit" do
      stub_const("Sirena::Conformance::CASE_TIMEOUT", 0.05)
      slow_engine = instance_double(Sirena::Engine)
      allow(slow_engine).to receive(:render) { sleep 2 && "<svg/>" }
      allow(Sirena::Engine).to receive(:new).and_return(slow_engine)

      expect(described_class.render("pie/b.mmd")).to be_nil
    end

    it "bounds every case by a limit short enough to finish the sweep" do
      allow(Timeout).to receive(:timeout).and_call_original

      described_class.render("pie/b.mmd")

      expect(Timeout).to have_received(:timeout).with(be_between(1, 60))
    end
  end

  describe ".render with a source that depends on today's date" do
    let(:name) { "gantt/010_parser_should_handle_a_dateformat_definition_9.mmd" }
    let(:source) { File.read(File.join(described_class::CORPUS_ROOT, name)) }

    it "renders as of 2026-01-01, whatever the date it runs on" do
      pinned = Sirena::Engine.new.render(source, today: Date.new(2026, 1, 1))
      later = Sirena::Engine.new.render(source, today: Date.new(2030, 6, 1))

      expect(later).not_to eq(pinned)
      expect(described_class.render(name)).to eq(pinned)
    end
  end

  describe ".rows" do
    it "records a rendered but nonconforming case as nonconformant" do
      allow(described_class).to receive(:render).with("x/1.mmd").and_return(invalid_svg)

      expect(described_class.rows(["x/1.mmd"])).to eq([row("x/1.mmd", "nonconformant")])
    end
  end

  describe ".diff" do
    it "names a case that was conformant and is now nonconformant" do
      diff = described_class.diff([row("a", "conformant")], [row("a", "nonconformant")])

      expect(diff).to eq(regressed: ["a"], stale: [])
    end

    it "names a case that was conformant and no longer renders" do
      diff = described_class.diff([row("a", "conformant")], [])

      expect(diff).to eq(regressed: ["a"], stale: [])
    end

    it "names a case that is conformant now and was not recorded as such" do
      diff = described_class.diff([row("a", "nonconformant")], [row("a", "conformant"), row("b", "conformant")])

      expect(diff).to eq(regressed: [], stale: %w[a b])
    end

    it "names a nonconformant case that appeared since the scoreboard was written" do
      diff = described_class.diff([row("a", "conformant")], [row("a", "conformant"), row("b", "nonconformant")])

      expect(diff).to eq(regressed: [], stale: ["b"])
    end

    it "names a nonconformant case that stopped rendering since the scoreboard was written" do
      diff = described_class.diff([row("a", "conformant"), row("b", "nonconformant")], [row("a", "conformant")])

      expect(diff).to eq(regressed: [], stale: ["b"])
    end

    it "names a swap: one case fixed while another breaks" do
      diff = described_class.diff(
        [row("a", "conformant"), row("b", "nonconformant")],
        [row("a", "nonconformant"), row("b", "conformant")]
      )

      expect(diff).to eq(regressed: ["a"], stale: ["b"])
    end

    it "reports nothing when the rows match" do
      rows = [row("a", "conformant"), row("b", "nonconformant")]

      expect(described_class.diff(rows, rows)).to eq(regressed: [], stale: [])
    end
  end

  describe ".summary" do
    it "derives the rate from the rows" do
      rows = [row("a", "conformant"), row("b", "nonconformant")]

      expect(described_class.summary(rows)).to eq("conformance: 1/2 rendered cases conformant (50.0%)")
    end

    it "reports zero rather than dividing by zero when nothing rendered" do
      expect(described_class.summary([])).to eq("conformance: 0/0 rendered cases conformant (0.0%)")
    end
  end

  describe ".record!" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "conformance.json") }

    before do
      stub_const("Sirena::Conformance::SCOREBOARD_PATH", path)
      allow(described_class).to receive(:rows).and_return([row("a/1.mmd", "conformant")])
    end

    after { FileUtils.remove_entry(dir) }

    it "writes the fresh rows and reports what it wrote" do
      expect(described_class.record!).to eq("conformance: 1/1 rendered cases conformant (100.0%)\nwrote #{path}")
      expect(described_class.load_scoreboard).to eq([row("a/1.mmd", "conformant")])
    end

    it "keeps the previous scoreboard when no case rendered" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])
      allow(described_class).to receive(:rows).and_return([])

      expect { described_class.record! }.to raise_error(described_class::RegressionError, /no corpus case rendered/)
      expect(described_class.load_scoreboard).to eq([row("a/1.mmd", "conformant")])
    end
  end

  describe ".check!" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "conformance.json") }

    before { stub_const("Sirena::Conformance::SCOREBOARD_PATH", path) }

    after { FileUtils.remove_entry(dir) }

    it "raises naming the case when a seeded nonconforming SVG replaces a conformant one" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])
      allow(described_class).to receive(:render).with("a/1.mmd").and_return(invalid_svg)

      expect { described_class.check!(described_class.rows(["a/1.mmd"])) }
        .to raise_error(described_class::RegressionError, /REGRESSED.*\n  a\/1\.mmd/)
    end

    it "raises naming a conformant case the scoreboard does not record" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])

      expect { described_class.check!([row("a/1.mmd", "conformant"), row("a/2.mmd", "conformant")]) }
        .to raise_error(described_class::RegressionError, /STALE.*\n  a\/2\.mmd/)
    end

    it "raises naming a nonconformant case the scoreboard does not record" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])

      expect { described_class.check!([row("a/1.mmd", "conformant"), row("a/2.mmd", "nonconformant")]) }
        .to raise_error(described_class::RegressionError, /STALE.*\n  a\/2\.mmd/)
    end

    it "names only the regressions when nothing is stale" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])

      expect { described_class.check!([row("a/1.mmd", "nonconformant")]) }
        .to raise_error(described_class::RegressionError) { |e| expect(e.message).not_to include("STALE") }
    end

    it "names only the stale cases when nothing regressed" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])

      expect { described_class.check!([row("a/1.mmd", "conformant"), row("a/2.mmd", "conformant")]) }
        .to raise_error(described_class::RegressionError) { |e| expect(e.message).not_to include("REGRESSED") }
    end

    it "raises before rendering anything when the scoreboard file is missing" do
      allow(described_class).to receive(:rows)

      expect { described_class.check! }.to raise_error(described_class::RegressionError, /missing/)
      expect(described_class).not_to have_received(:rows)
    end

    it "returns the summary when the rows match the scoreboard" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])

      expect(described_class.check!([row("a/1.mmd", "conformant")]))
        .to eq("conformance:check: clean (conformance: 1/1 rendered cases conformant (100.0%))")
    end

    it "raises naming a case the scoreboard records twice, even when the later row agrees with the fresh run" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant"), row("a/1.mmd", "nonconformant")])

      expect { described_class.check!([row("a/1.mmd", "nonconformant")]) }
        .to raise_error(described_class::RegressionError, /more than one row for: a\/1\.mmd/)
    end

    [
      ["a row with no status", [{ "case" => "a/1.mmd" }]],
      ["a row with an unknown status", [{ "case" => "a/1.mmd", "status" => "passed" }]],
      ["a row with no case", [{ "status" => "conformant" }]],
      ["a row whose case is not a string", [{ "case" => 7, "status" => "conformant" }]],
      ["a row that is not an object", [1]],
      ["a null row", [nil]],
      ["a row that is a list", [["a/1.mmd", "conformant"]]],
      ["a document that is not a list of rows", { "a/1.mmd" => "conformant" }],
      ["a null document", nil]
    ].each do |description, content|
      it "raises on #{description}" do
        File.write(path, JSON.generate(content))

        expect { described_class.check!([]) }.to raise_error(described_class::RegressionError, /not a list|malformed/)
      end
    end

    it "raises on a scoreboard that is not valid JSON, before rendering anything" do
      File.write(path, "[")
      allow(described_class).to receive(:rows)

      expect { described_class.check! }.to raise_error(described_class::RegressionError, /not valid JSON/)
      expect(described_class).not_to have_received(:rows)
    end

    it "leaves the previous scoreboard and no temp file behind when the write fails" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])
      allow(File).to receive(:rename).and_raise(Errno::EIO)

      expect { described_class.write_scoreboard([row("a/2.mmd", "conformant")]) }.to raise_error(Errno::EIO)
      expect(Dir.children(dir)).to eq(["conformance.json"])
      expect(described_class.load_scoreboard).to eq([row("a/1.mmd", "conformant")])
    end

    it "writes through a temp file no other process shares" do
      temp_paths = [111, 222].map do |pid|
        allow(Process).to receive(:pid).and_return(pid)
        written_through = nil
        allow(File).to receive(:rename).and_wrap_original do |rename, from, to|
          written_through = from
          rename.call(from, to)
        end
        described_class.write_scoreboard([row("a/1.mmd", "conformant")])
        written_through
      end

      expect(temp_paths.uniq.size).to eq(2)
    end

    it "round-trips rows through the file" do
      described_class.write_scoreboard([row("a/1.mmd", "conformant")])

      expect(described_class.load_scoreboard).to eq([row("a/1.mmd", "conformant")])
    end
  end

  describe "the conformance:check task" do
    let(:application) { Rake::Application.new }

    before do
      Rake.with_application(application) { load File.expand_path("../../tasks/conformance.rake", __dir__) }
    end

    it "records through the conformance task" do
      allow(described_class).to receive(:record!).and_return("recorded")

      expect { application["conformance"].invoke }.to output("recorded\n").to_stdout
      expect(described_class).to have_received(:record!)
    end

    it "exits non-zero and prints what regressed" do
      allow(described_class).to receive(:check!).and_raise(described_class::RegressionError, "REGRESSED\n  a/1.mmd")

      expect { application["conformance:check"].invoke }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output("REGRESSED\n  a/1.mmd\nconformance:check: FAILED\n").to_stderr
    end

    it "prints the summary and exits zero when nothing drifted" do
      allow(described_class).to receive(:check!).and_return("conformance:check: clean (ok)")

      expect { application["conformance:check"].invoke }.to output("conformance:check: clean (ok)\n").to_stdout
    end
  end

  describe "the committed scoreboard" do
    it "records every rendered corpus case, all conformant" do
      expect(described_class.check!).to start_with("conformance:check: clean")
    end
  end
end
