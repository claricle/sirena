# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::StateDiagram do
  subject(:renderer) { described_class.new }

  def xml_for(graph)
    renderer.render(graph).to_xml
  end

  describe "canvas size" do
    it "defaults to 800x600 plus padding when there are no children key" do
      xml = xml_for({ id: "s" })
      expect(xml).to include('width="840.0"').and include('height="640.0"')
    end

    it "pads an empty children list from the 800x600 default" do
      xml = xml_for({ id: "s", children: [] })
      expect(xml).to include('width="900.0"').and include('height="700.0"')
    end

    it "assumes 100x50 for states with no geometry" do
      xml = xml_for({ id: "s", children: [{ id: "a" }] })
      expect(xml).to include('width="200.0"').and include('height="150.0"')
    end
  end

  describe "states" do
    let(:graph) do
      { id: "s",
        children: [
          { id: "a" },
          { id: "b", x: 200, y: 0, labels: [{ text: "B" }, { text: "b2" }],
            metadata: { shape_type: "choice" } },
          { id: "c", metadata: { state_type: "start" } },
        ],
        edges: [] }
    end

    let(:default_rect) do
      '<rect fill="#ffffff" stroke="#000000" stroke-width="2" ' \
        'x="0.0" y="0.0" width="100.0" height="50.0"'
    end
    let(:label_attrs) do
      'text-anchor="middle" font-family="Arial, sans-serif"'
    end

    it "renders a geometry-less state as a default 100x50 rounded rect " \
       "with no label" do
      expect(xml_for(graph)).to include(default_rect)
    end

    it "prefers metadata shape_type and stacks two labels at 14 and 12 point",
       :aggregate_failures do
      xml = xml_for(graph)
      expect(xml).to include('points="250,0 300,25 250,50 200,25"')
      expect(xml).to include(%(y="19.9" #{label_attrs} font-size="14">B<))
      expect(xml).to include(%(y="39.2" #{label_attrs} font-size="12">b2<))
    end

    it "falls back to state_type for a start circle" do
      expect(xml_for(graph)).to include(
        '<circle fill="#000000" stroke="none" cx="50.0" cy="25.0" r="25.0"/>',
      )
    end

    it "does not label a state whose labels list is empty" do
      xml = xml_for({ id: "s", children: [{ id: "a", labels: [] }] })
      expect(xml).not_to include("<text")
    end
  end

  describe "transitions" do
    let(:children) { [{ id: "a" }, { id: "b", x: 200, y: 0 }] }

    def transition(id, **extra)
      { id: id, sources: ["a"], targets: ["b"], **extra }
    end

    it "routes through bend points and labels at the midpoint",
       :aggregate_failures do
      t = transition("e", labels: [{ text: "go" }],
                          sections: [{ bendPoints: [{ x: 5, y: 6 }] }])
      xml = xml_for({ id: "s", children: children, edges: [t] })
      expect(xml).to include('d="M 50 25 L 5 6 L 250 25"')
      expect(xml).to include('x="150.0" y="17.0"').and include(">go<")
    end

    it "draws a straight line for empty sections, sections without bends, " \
       "and empty bends" do
      ts = [transition("f", sections: [{}]), transition("g", sections: []),
            transition("h", sections: [{ bendPoints: [] }]), transition("i")]
      xml = xml_for({ id: "s", children: children, edges: ts })
      expect(xml.scan('d="M 50 25 L 250 25"').size).to eq(4)
    end

    it "emits no text for an empty label list" do
      xml = xml_for({ id: "s", children: children,
                      edges: [transition("j", labels: [])] })
      expect(xml).not_to include("<text")
    end

    it "drops transitions whose endpoints cannot be found" do
      ts = [{ id: "k", sources: ["zz"], targets: ["b"] },
            { id: "l", sources: nil, targets: ["b"] },
            { id: "m", sources: ["a"], targets: [] }]
      xml = xml_for({ id: "s", children: children, edges: ts })
      expect(xml).not_to include("transition-")
    end

    it "finds no endpoint when the graph has no children" do
      xml = xml_for({ id: "s", edges: [transition("n")] })
      expect(xml).not_to include("transition-n")
    end
  end
end
