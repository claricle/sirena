# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/c4"

module C4BranchHelpers
  def node(id, kind, **extra)
    { id: id, x: 10, y: 20, width: 100, height: 60,
      labels: [{ text: id }], metadata: { kind => true, **extra } }
  end

  def xml_for(graph)
    described_class.new.render(graph).to_xml
  end
end

RSpec.describe Sirena::Renderer::C4 do
  include C4BranchHelpers

  describe "canvas size" do
    it "falls back to 800x600 when there are no children" do
      xml = xml_for({ id: "c4" })
      expect(xml).to include('width="840.0"').and include('height="640.0"')
    end

    context "with a nested child and a child without a position" do
      let(:inner) do
        { id: "in", x: 300, y: 400, width: 50, height: 50,
          metadata: { system: true } }
      end
      let(:outer) do
        { id: "b", x: 0, y: 0, width: 100, height: 100, children: [inner],
          metadata: { boundary_type: "Enterprise" } }
      end
      let(:noisy) { { id: "n", metadata: { system: true } } }

      it "pads the rightmost and bottommost child, descending into children" do
        xml = xml_for({ id: "c4", children: [outer, noisy] })
        expect(xml).to include('width="430.0"').and include('height="530.0"')
      end
    end
  end

  describe "elements" do
    it "uses the external person and system palettes" do
      xml = xml_for({ id: "c4", children: [node("p", :person, external: true),
                                           node("s", :system,
                                                external: true)] })
      expect(xml).to include("#6C6477").and include("#8F8F8F")
    end

    it "renders container and component colours" do
      xml = xml_for({ id: "c4",
                      children: [node("c", :container),
                                 node("k", :component)] })
      expect(xml).to include("#438DD5").and include("#85BBF0")
    end

    it "defaults an unclassified element to a system box" do
      xml = xml_for({ id: "c4",
                      children: [{ id: "x", x: 1, y: 2, width: 10, height: 10,
                                   metadata: {} }] })
      expect(xml).to include("#1168BD")
    end

    it "uses default dimensions when width and height are absent" do
      child = { id: "p", x: 0, y: 0, metadata: { person: true } }
      xml = xml_for({ id: "c4", children: [child] })
      expect(xml).to include('width="140.0"').and include('height="180.0"')
    end

    it "skips elements without a position or without metadata",
       :aggregate_failures do
      no_position = { id: "a", metadata: { system: true } }
      no_metadata = { id: "b", x: 1, y: 1, width: 5, height: 5 }
      xml = xml_for({ id: "c4", children: [no_position, no_metadata] })
      expect(xml).not_to include("element-a")
      expect(xml).not_to include("element-b")
    end

    it "sizes label fonts by index" do
      labels = %w[A B C D].map { |text| { text: text } }
      el = node("s", :system).merge(labels: labels)
      xml = xml_for({ id: "c4", children: [el] })
      expect(xml.scan(/font-size="(\d+)"/).flatten).to eq(%w[14 11 10 10])
    end
  end

  describe "boundaries" do
    let(:boundary) do
      { id: "b", x: 5, y: 5, width: 300, height: 300, labels: [{ text: "Bnd" }],
        metadata: { boundary_type: "System" },
        children: [node("inner", :container),
                   { id: "nb", x: 6, y: 6, width: 50, height: 50,
                     metadata: { boundary_type: "Container" } }] }
    end

    let(:bare) do
      { id: "q", width: 1, height: 1, metadata: { boundary_type: "System" } }
    end
    let(:unlabeled) do
      { id: "u", x: 1, y: 1, width: 9, height: 9,
        metadata: { boundary_type: "System" } }
    end

    it "renders the boundary, its label, nested boundaries and child elements",
       :aggregate_failures do
      xml = xml_for({ id: "c4", children: [boundary] })
      expect(xml).to include("boundary-b").and include("boundary-nb")
        .and include("element-inner")
      expect(xml).to include(">Bnd<")
    end

    it "skips a boundary with no position and ignores a label-less one",
       :aggregate_failures do
      xml = xml_for({ id: "c4", children: [bare, unlabeled] })
      expect(xml).not_to include("boundary-q")
      expect(xml).to include("boundary-u")
    end
  end

  describe "relationships" do
    let(:a) { node("a", :system).merge(x: 0) }
    let(:b) { node("b", :system).merge(x: 400) }

    let(:bidirectional) do
      edge(["a"], ["b"], labels: [{ text: "uses" }, { text: "HTTPS" }],
                         metadata: { bidirectional: true })
    end

    def edge(sources, targets, **extra)
      { id: "e1", sources: sources, targets: targets, **extra }
    end

    it "draws a labelled bidirectional arrow with two arrowheads",
       :aggregate_failures do
      xml = xml_for({ id: "c4", children: [a, b], edges: [bidirectional] })
      expect(xml.scan("<polygon").size).to eq(2)
      expect(xml).to include('font-size="12">uses<')
        .and include('font-size="10">HTTPS<')
    end

    it "points the arrowhead left when the target is left of the source" do
      graph = { id: "c4", children: [a, b], edges: [edge(["b"], ["a"])] }
      xml = xml_for(graph)
      expect(xml).to include('points="50,50 58,46 58,54"')
    end

    it "omits edges with missing endpoints or unknown node ids" do
      edges = [edge(nil, ["b"]), edge(["a"], nil), edge(["zz"], ["b"]),
               edge(["a"], ["zz"])]
      xml = xml_for({ id: "c4", children: [a, b], edges: edges })
      expect(xml).not_to include("<polygon")
    end

    it "does not map boundaries as relationship endpoints" do
      bnd = { id: "bb", x: 0, y: 0, width: 10, height: 10,
              metadata: { boundary_type: "System" } }
      xml = xml_for({ id: "c4", children: [bnd, b],
                      edges: [edge(["bb"], ["b"])] })
      expect(xml).not_to include("<polygon")
    end
  end
end
