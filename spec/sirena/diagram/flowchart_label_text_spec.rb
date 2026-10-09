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

    it "draws an edge label without markup" do
      svg = Sirena.render("graph TD\nA -->|\"fa:fa-car go<br/>now\"| B\n")
      drawn = Nokogiri::XML(svg).remove_namespaces!.xpath("//text").map { |t| t.text.strip }
      expect(drawn).to include("go now")
    end
  end
end
