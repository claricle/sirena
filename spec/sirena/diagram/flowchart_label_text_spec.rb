# frozen_string_literal: true

require "spec_helper"
require "nokogiri"

RSpec.describe Sirena::Diagram::FlowchartLabelText do
  # [source, label owner id, text mermaid draws]
  cases = [
    ['A["quoted"]', "A", "quoted"],
    ["A[fa:fa-car Car]", "A", "Car"],
    ["A[This is a<br/>two line]", "A", "This is a two line"],
    ["A{A <br> end}", "A", "A end"],
    ["A[\"<a href='x'>AAA</a>\"]", "A", "AAA"],
    ["A[\\\\This has a \\\\ as text\\\\]", "A", "\\This has a \\ as text\\"],
    ["A(c:\\\\windows)", "A", "c:\\windows"],
  ]

  describe "rendered flowchart text" do
    cases.each do |source, _owner, expected|
      it "draws #{source.inspect} as #{expected.inspect}" do
        svg = Sirena.render("graph TD;\n#{source}\n")
        drawn = Nokogiri::XML(svg).remove_namespaces!.xpath("//text").map { |t| t.text.strip }
        expect(drawn).to include(expected)
      end
    end

    it "draws a subgraph title without its quote marks" do
      svg = Sirena.render("graph TD\nsubgraph one[\"the title\"]\nA\nend\n")
      drawn = Nokogiri::XML(svg).remove_namespaces!.xpath("//text").map { |t| t.text.strip }
      expect(drawn).to include("the title")
    end

    # mmdc stacks a `<br>` label at 24px a line, centred on the node.
    it "draws a node label's lines 24px apart, centred on the node" do
      svg = Sirena.render("graph TD;a{{A <br> end}};")
      doc = Nokogiri::XML(svg).remove_namespaces!
      first = doc.at_xpath("//text")["y"].to_f
      second = doc.xpath("//text/tspan").last["y"].to_f
      rows = doc.at_xpath("//polygon")["points"].split.map { |pair| pair.split(",").last.to_f }

      expect(second - first).to eq(24.0)
      expect(((first + second) / 2) - (0.35 * 16)).to be_within(0.01).of(rows.minmax.sum / 2)
    end

    it "draws an edge label without markup" do
      svg = Sirena.render("graph TD\nA -->|\"fa:fa-car go<br/>now\"| B\n")
      drawn = Nokogiri::XML(svg).remove_namespaces!.xpath("//text").map { |t| t.text.strip }
      expect(drawn).to include("go now")
    end
  end

  describe ".lines" do
    # [label as written, lines mermaid draws]
    [
      ["A <br> end", %w[A end]],
      ["one<br/>two<BR />three", %w[one two three]],
      ["\"This is a\nmultiline\"", ["This is a", "multiline"]],
      ["fa:fa-car <b>Car</b>", ["Car"]],
      ["plain", ["plain"]],
      ["", [""]],
      [nil, [""]],
    ].each do |written, expected|
      it "splits #{written.inspect} into #{expected.inspect}" do
        expect(described_class.lines(written)).to eq(expected)
      end
    end
  end

  describe ".display" do
    it "returns nil for a missing label" do
      expect(described_class.display(nil)).to be_nil
    end
  end
end
