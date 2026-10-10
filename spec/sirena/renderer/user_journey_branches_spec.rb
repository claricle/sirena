# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/user_journey"

RSpec.describe Sirena::Renderer::UserJourney do
  subject(:renderer) { described_class.new }

  let(:colors) { Sirena::Theme::Registry.get(:default).colors }

  def xml_for(graph)
    renderer.render(graph).to_xml
  end

  describe "canvas size" do
    it "falls back to 800x600 with no children key" do
      xml = xml_for({ id: "u" })
      expect(xml).to include('width="840.0"').and include('height="640.0"')
    end

    it "pads an empty children list from the 800x600 default" do
      xml = xml_for({ id: "u", children: [] })
      expect(xml).to include('width="880.0"').and include('height="700.0"')
    end
  end

  describe "tasks" do
    let(:tasks) do
      [
        { id: "t1" },
        { id: "t2", x: 300, y: 10,
          metadata: { score_color: :green, name: "N", score: 4,
                      actors: %w[Me You], section_name: "S" } },
      ]
    end

    let(:section_headers) do
      /font-size="16" font-weight="bold">([^<]+)</
    end
    let(:default_box) do
      "<rect fill=\"#{colors.warning}\" stroke=\"#{colors.node_stroke}\" " \
        'stroke-width="2" ' \
        'x="0.0" y="0.0" width="120.0" height="80.0"'
    end

    it "defaults a bare task to a yellow 120x80 box named Task with " \
       "score 3 and no actors", :aggregate_failures do
      xml = xml_for({ id: "u", children: [tasks.first] })
      expect(xml).to include(default_box)
      expect(xml).to include('font-weight="bold">Task<')
        .and include('font-weight="bold">3<')
      expect(xml).to include('font-size="11"></text>')
    end

    it "puts tasks without a section under Default and named sections " \
       "under their own header", :aggregate_failures do
      xml = xml_for({ id: "u", children: tasks })
      expect(xml.scan(section_headers).flatten).to eq(%w[Default S])
      expect(xml).to include("fill=\"#{colors.success}\"")
        .and include(">Me, You<")
    end

    it "skips the title when it is empty", :aggregate_failures do
      graph = { id: "u", children: [tasks.first] }
      xml = xml_for(graph.merge(metadata: { title: "" }))
      titled = xml_for(graph.merge(metadata: { title: "T" }))
      expect(xml).not_to include('font-size="20"')
      expect(titled).to include('font-size="20" font-weight="bold">T<')
    end
  end

  describe "timeline arrows" do
    let(:children) { [{ id: "t1" }, { id: "t2", x: 300, y: 10 }] }

    it "draws a line from the right of the source to the left of the target",
       :aggregate_failures do
      edge = { id: "e1", sources: ["t1"], targets: ["t2"] }
      xml = xml_for({ id: "u", children: children, edges: [edge] })
      expect(xml).to include('<g id="arrow-e1">')
      expect(xml).to include('x1="120.0" y1="40.0" x2="300.0" y2="50.0"')
    end

    it "omits arrows with missing or unknown endpoints" do
      edges = [{ id: "e2", sources: nil, targets: ["t2"] },
               { id: "e3", sources: ["zz"], targets: ["t2"] },
               { id: "e4", sources: ["t1"], targets: nil }]
      xml = xml_for({ id: "u", children: children, edges: edges })
      expect(xml).not_to include("arrow-")
    end

    it "finds no endpoints when the graph has no children" do
      edge = { id: "e5", sources: ["t1"], targets: ["t2"] }
      expect(xml_for({ id: "u", edges: [edge] })).not_to include("arrow-")
    end
  end
end
