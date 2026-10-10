# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../scripts/audit_singleton_captures"

RSpec.describe AuditSingletonCaptures do
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  describe ".calls_in" do
    let(:path) { File.join(root, "parser.rb") }

    before do
      File.write(path, <<~RUBY)
        # Array(commented_capture)
        description = "Array(string_capture)"
        values = Array(captured_values)
      RUBY
    end

    it "finds executable Array calls without counting prose or strings" do
      calls = described_class.calls_in(path, root: root)

      expect(calls.map { |call| [call.path, call.line, call.source] })
        .to eq([["parser.rb", 3, "values = Array(captured_values)"]])
    end
  end

  describe ".paths_for_stem" do
    it "refuses to report a misleading zero when a type has no source path" do
      expect { described_class.paths_for_stem("missing", root: root) }
        .to raise_error(
          ArgumentError,
          /no parser, grammar, builder, or transform path for missing/,
        )
    end
  end

  describe ".render" do
    it "classifies every sub-track" do
      report = described_class.render(root: described_class::ROOT)

      expect(report.scan(/^## 07[a-f]\b/).size).to eq(6)
    end

    it "records explicit zero-hit evidence" do
      report = described_class.render(root: described_class::ROOT)
      section = report.split("## 07e").last.split("## 07f").first

      expect(section).to include("**Result:** zero `Array(...)` hits")
    end

    it "records exact hit locations" do
      report = described_class.render(root: described_class::ROOT)

      expect(report).to include("lib/sirena/parser/builders/class_diagram.rb")
    end

    it "is deterministic" do
      first = described_class.render(root: described_class::ROOT)
      second = described_class.render(root: described_class::ROOT)

      expect(second).to eq(first)
    end
  end

  describe ".check" do
    let(:stale_result) do
      [false, "singleton-capture audit is stale; regenerate with " \
              "`ruby scripts/audit_singleton_captures.rb --write`"]
    end

    before do
      FileUtils.mkdir_p(File.join(root, "docs"))
      File.write(File.join(root, described_class::DOCUMENT_PATH), document)
      allow(described_class).to receive(:render)
        .with(root: root).and_return("fresh\n")
    end

    context "with a stale document" do
      let(:document) { "stale\n" }

      it "rejects it" do
        expect(described_class.check(root: root)).to eq(stale_result)
      end
    end

    context "with the exact generated document" do
      let(:document) { "fresh\n" }

      it "accepts it" do
        expect(described_class.check(root: root))
          .to eq([true, "singleton-capture audit: current"])
      end
    end
  end

  describe "the committed document" do
    it "matches the current source scan" do
      expect(described_class.check(root: described_class::ROOT))
        .to eq([true, "singleton-capture audit: current"])
    end
  end
end
