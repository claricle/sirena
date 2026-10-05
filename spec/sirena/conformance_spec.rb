# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"
require "fileutils"
require_relative "../../tasks/support/conformance"

module ConformanceSpecHelpers
  def row(name, status)
    { "case" => name, "status" => status }
  end

  def conformant(name)
    row(name, "conformant")
  end

  def nonconformant(name)
    row(name, "nonconformant")
  end

  def seed_scoreboard(*rows)
    described_class.write_scoreboard(rows)
  end

  def regression(pattern)
    raise_error(described_class::RegressionError, pattern)
  end

  def message_without(text)
    raise_error(described_class::RegressionError,
                satisfy { |message| !message.include?(text) })
  end

  def stub_render(name, svg)
    allow(described_class).to receive(:render).with(name).and_return(svg)
  end

  def written_through(pid, *rows)
    allow(Process).to receive(:pid).and_return(pid)
    source = nil
    allow(File).to receive(:rename).and_wrap_original do |rename, from, to|
      source = from
      rename.call(from, to)
    end
    seed_scoreboard(*rows)
    source
  end

  def attempt
    yield
  rescue described_class::RegressionError, Errno::EIO
    nil
  end

  def valid_svg
    svg_with('<rect width="1" height="1"/>')
  end

  def invalid_svg
    svg_with("<script>x</script>")
  end

  def malformed_svg
    svg_with("<text>a & b</text>")
  end

  def svg_with(body)
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\">" \
      "#{body}</svg>"
  end
end

RSpec.describe Sirena::Conformance do
  include ConformanceSpecHelpers

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
      File.write(File.join(root, "pie", "a.mmd"),
                 "notADiagramType\n  A --> B\n")
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
      expect(described_class.rows).to eq([conformant("pie/b.mmd")])
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
    let(:name) do
      "gantt/010_parser_should_handle_a_dateformat_definition_9.mmd"
    end
    let(:source) { File.read(File.join(described_class::CORPUS_ROOT, name)) }
    let(:engine) { Sirena::Engine.new }
    let(:pinned) { engine.render(source, today: Date.new(2026, 1, 1)) }

    it "depends on the date, so the render has to be pinned" do
      later = engine.render(source, today: Date.new(2030, 6, 1))

      expect(later).not_to eq(pinned)
    end

    it "renders as of 2026-01-01, whatever the date it runs on" do
      expect(described_class.render(name)).to eq(pinned)
    end
  end

  describe ".rows" do
    it "records a rendered but nonconforming case as nonconformant" do
      stub_render("x/1.mmd", invalid_svg)

      expect(described_class.rows(["x/1.mmd"]))
        .to eq([nonconformant("x/1.mmd")])
    end
  end

  describe ".diff" do
    it "names a case that was conformant and is now nonconformant" do
      diff = described_class.diff([conformant("a")], [nonconformant("a")])

      expect(diff).to eq(regressed: ["a"], stale: [])
    end

    it "names a case that was conformant and no longer renders" do
      diff = described_class.diff([conformant("a")], [])

      expect(diff).to eq(regressed: ["a"], stale: [])
    end

    it "names a case that is conformant now and was not recorded as such" do
      diff = described_class.diff([nonconformant("a")],
                                  [conformant("a"), conformant("b")])

      expect(diff).to eq(regressed: [], stale: %w[a b])
    end

    it "names a nonconformant case that appeared since the file was written" do
      diff = described_class.diff([conformant("a")],
                                  [conformant("a"), nonconformant("b")])

      expect(diff).to eq(regressed: [], stale: ["b"])
    end

    it "names a nonconformant case that stopped rendering since then" do
      diff = described_class.diff([conformant("a"), nonconformant("b")],
                                  [conformant("a")])

      expect(diff).to eq(regressed: [], stale: ["b"])
    end

    it "names a swap: one case fixed while another breaks" do
      diff = described_class.diff([conformant("a"), nonconformant("b")],
                                  [nonconformant("a"), conformant("b")])

      expect(diff).to eq(regressed: ["a"], stale: ["b"])
    end

    it "reports nothing when the rows match" do
      rows = [conformant("a"), nonconformant("b")]

      expect(described_class.diff(rows, rows)).to eq(regressed: [], stale: [])
    end
  end

  describe ".summary" do
    it "derives the rate from the rows" do
      summary = described_class.summary([conformant("a"), nonconformant("b")])

      expect(summary)
        .to eq("conformance: 1/2 rendered cases conformant (50.0%)")
    end

    it "rounds a half-way rate the way printf does" do
      rows = [conformant("a")] + Array.new(15) { |i| nonconformant("b#{i}") }

      expect(described_class.summary(rows))
        .to eq("conformance: 1/16 rendered cases conformant (6.2%)")
    end

    it "reports zero rather than dividing by zero when nothing rendered" do
      expect(described_class.summary([]))
        .to eq("conformance: 0/0 rendered cases conformant (0.0%)")
    end
  end

  describe ".record!" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "conformance.json") }
    let(:wrote) do
      "conformance: 1/1 rendered cases conformant (100.0%)\nwrote #{path}"
    end

    before do
      stub_const("Sirena::Conformance::SCOREBOARD_PATH", path)
      allow(described_class).to receive(:rows)
        .and_return([conformant("a/1.mmd")])
    end

    after { FileUtils.remove_entry(dir) }

    it "reports what it wrote" do
      expect(described_class.record!).to eq(wrote)
    end

    it "writes the fresh rows" do
      described_class.record!

      expect(described_class.load_scoreboard).to eq([conformant("a/1.mmd")])
    end

    it "refuses to record when no case rendered" do
      allow(described_class).to receive(:rows).and_return([])

      expect do
        described_class.record!
      end.to regression(/no corpus case rendered/)
    end

    it "refuses and keeps the previous scoreboard when nothing rendered",
       :aggregate_failures do
      seed_scoreboard(conformant("a/1.mmd"))
      allow(described_class).to receive(:rows).and_return([])

      expect { described_class.record! }.to regression(/no corpus case/)
      expect(described_class.load_scoreboard).to eq([conformant("a/1.mmd")])
    end
  end

  describe ".check!" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "conformance.json") }
    let(:good) { conformant("a/1.mmd") }

    before { stub_const("Sirena::Conformance::SCOREBOARD_PATH", path) }

    after { FileUtils.remove_entry(dir) }

    it "names the case when a seeded nonconforming SVG replaces a good one" do
      seed_scoreboard(good)
      stub_render("a/1.mmd", invalid_svg)
      fresh = described_class.rows(["a/1.mmd"])

      expect { described_class.check!(fresh) }
        .to regression(%r{REGRESSED.*\n {2}a/1\.mmd})
    end

    it "names a conformant case the scoreboard does not record" do
      seed_scoreboard(good)
      fresh = [good, conformant("a/2.mmd")]

      expect { described_class.check!(fresh) }
        .to regression(%r{STALE.*\n {2}a/2\.mmd})
    end

    it "names a nonconformant case the scoreboard does not record" do
      seed_scoreboard(good)
      fresh = [good, nonconformant("a/2.mmd")]

      expect { described_class.check!(fresh) }
        .to regression(%r{STALE.*\n {2}a/2\.mmd})
    end

    it "names only the regressions when nothing is stale" do
      seed_scoreboard(good)

      expect { described_class.check!([nonconformant("a/1.mmd")]) }
        .to message_without("STALE")
    end

    it "names only the stale cases when nothing regressed" do
      seed_scoreboard(good)

      expect { described_class.check!([good, conformant("a/2.mmd")]) }
        .to message_without("REGRESSED")
    end

    it "raises when the scoreboard file is missing" do
      expect { described_class.check! }.to regression(/missing/)
    end

    it "renders nothing when the scoreboard file is missing" do
      allow(described_class).to receive(:rows)
      attempt { described_class.check! }

      expect(described_class).not_to have_received(:rows)
    end

    it "returns the summary when the rows match the scoreboard" do
      seed_scoreboard(good)

      expect(described_class.check!([good])).to eq(
        "conformance:check: clean " \
        "(conformance: 1/1 rendered cases conformant (100.0%))",
      )
    end

    it "names a case recorded twice, though the later row agrees" do
      seed_scoreboard(good, nonconformant("a/1.mmd"))

      expect { described_class.check!([nonconformant("a/1.mmd")]) }
        .to regression(%r{more than one row for: a/1\.mmd})
    end

    [
      ["a row with no status", [{ "case" => "a/1.mmd" }]],
      ["a row with an unknown status",
       [{ "case" => "a/1.mmd", "status" => "passed" }]],
      ["a row with no case", [{ "status" => "conformant" }]],
      ["a row whose case is not a string",
       [{ "case" => 7, "status" => "conformant" }]],
      ["a row that is not an object", [1]],
      ["a null row", [nil]],
      ["a row that is a list", [["a/1.mmd", "conformant"]]],
      ["a document that is not a list of rows", { "a/1.mmd" => "conformant" }],
      ["a null document", nil],
    ].each do |description, content|
      it "raises on #{description}" do
        File.write(path, JSON.generate(content))

        expect do
          described_class.check!([])
        end.to regression(/not a list|malformed/)
      end
    end

    it "raises on a scoreboard that is not valid JSON" do
      File.write(path, "[")

      expect { described_class.check! }.to regression(/not valid JSON/)
    end

    it "reads a scoreboard that is not valid JSON before rendering anything" do
      File.write(path, "[")
      allow(described_class).to receive(:rows)
      attempt { described_class.check! }

      expect(described_class).not_to have_received(:rows)
    end

    it "raises the failure and leaves no temp file when the write fails",
       :aggregate_failures do
      seed_scoreboard(good)
      allow(File).to receive(:rename).and_raise(Errno::EIO)

      expect { seed_scoreboard(good) }.to raise_error(Errno::EIO)
      expect(Dir.children(dir)).to eq(["conformance.json"])
    end

    it "leaves the previous scoreboard when the write fails" do
      seed_scoreboard(good)
      allow(File).to receive(:rename).and_raise(Errno::EIO)
      attempt { seed_scoreboard(conformant("a/2.mmd")) }

      expect(described_class.load_scoreboard).to eq([good])
    end

    it "writes through a temp file no other process shares" do
      temp_paths = [111, 222].map { |pid| written_through(pid, good) }

      expect(temp_paths.uniq.size).to eq(2)
    end

    it "round-trips rows through the file" do
      seed_scoreboard(good)

      expect(described_class.load_scoreboard).to eq([good])
    end
  end

  describe "the conformance:check task" do
    let(:application) { Rake::Application.new }
    let(:rake_file) do
      File.expand_path("../../tasks/conformance.rake", __dir__)
    end
    let(:failed) { having_attributes(status: 1) }

    before do
      Rake.with_application(application) { load rake_file }
    end

    it "prints what record! returned", :aggregate_failures do
      allow(described_class).to receive(:record!).and_return("recorded")

      expect { application["conformance"].invoke }
        .to output("recorded\n").to_stdout
      expect(described_class).to have_received(:record!)
    end

    context "when a case regressed" do
      before do
        allow(described_class).to receive(:check!)
          .and_raise(described_class::RegressionError, "REGRESSED\n  a/1.mmd")
      end

      it "exits through abort with the failure line" do
        expect { application["conformance:check"].invoke }
          .to raise_error(SystemExit, "conformance:check: FAILED")
          .and output(/REGRESSED/).to_stderr
      end

      it "exits with status 1" do
        expect { application["conformance:check"].invoke }
          .to raise_error(an_instance_of(SystemExit).and(failed))
          .and output.to_stderr
      end

      it "prints what regressed" do
        expect { application["conformance:check"].invoke }
          .to raise_error(SystemExit)
          .and output("REGRESSED\n  a/1.mmd\nconformance:check: FAILED\n")
          .to_stderr
      end
    end

    it "prints the summary and exits zero when nothing drifted" do
      allow(described_class).to receive(:check!)
        .and_return("conformance:check: clean (ok)")

      expect { application["conformance:check"].invoke }
        .to output("conformance:check: clean (ok)\n").to_stdout
    end
  end

  describe "the committed scoreboard" do
    it "records every rendered corpus case, all conformant" do
      expect(described_class.check!).to start_with("conformance:check: clean")
    end
  end
end
