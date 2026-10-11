# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  let(:scene) do
    case_path = File.expand_path(
      "../../mermaid/class_diagram/" \
      "classdiagram_elk_v3_spec-76ab7ba5.mmd",
      __dir__,
    )
    source = File.read(case_path)
    diagram = Sirena::Parser::ClassDiagram.new.parse(source)

    described_class.new.call(diagram)
  end
  let(:source_node) { scene.children.find { |node| node.id == "C1" } }
  let(:target_node) { scene.children.find { |node| node.id == "C2" } }
  let(:section) { scene.edges.fetch(0).sections.fetch(0) }

  def center(node)
    node.x + (node.width / 2)
  end

  def placement_geometry(source, target)
    [source.x, source.y, center(source),
     target.y - source.y - source.height]
  end

  def route_geometry(edge_section)
    [edge_section.end_point.x, edge_section.start_point.y,
     edge_section.end_point.y]
  end

  def placed_coordinates(candidate)
    described_class.apply(candidate)
    candidate[:children].map { |child| [child[:x], child[:y]] }
  end

  def reversed_widths
    [
      { id: "B", width: 120, height: 80, metadata: {} },
      { id: "A", width: 80, height: 80, metadata: {} },
    ]
  end

  it "places the connected pair in a centered vertical lane" do
    expected = [Sirena::Layout::Grid::MARGIN, 50.0, center(target_node), 50]
    expect(placement_geometry(source_node, target_node)).to eq(expected)
  end

  it "routes the source-to-target edge vertically between the boxes" do
    expected = [section.start_point.x, source_node.y + source_node.height,
                target_node.y]
    expect(route_geometry(section)).to eq(expected)
  end

  describe Sirena::Layout::ClassCellPlacement do
    let(:graph) do
      lambda do |children = nil|
        children ||= [
          { id: "A", width: 100, height: 80, metadata: {} },
          { id: "B", width: 100, height: 80, metadata: {} },
        ]
        {
          children: children,
          edges: [{ id: "edge", sources: ["A"], targets: ["B"] }],
          layoutOptions: { "elk.direction" => "DOWN" },
        }
      end
    end

    it "keeps caller-selected coordinates for a matching pair" do
      candidate = graph.call
      candidate[:children].first[:x] = 7
      candidate[:children].last[:y] = 13
      expect(placed_coordinates(candidate)).to eq([[7, 50], [50.0, 13]])
    end

    it "orders by edge direction and centers against the wider box" do
      expect(placed_coordinates(graph.call(reversed_widths)))
        .to eq([[50.0, 180.0], [70.0, 50]])
    end

    packed = [[50, 50], [200.0, 50]]
    gridded = [[50, 50], [300, 50]]
    {
      "non-down direction" => [lambda { |value|
        value[:layoutOptions]["elk.direction"] = "RIGHT"
      }, packed],
      "note child" => [lambda { |value|
        value[:children].last[:metadata][:note] = true
      }, packed],
      "nested child" => [lambda { |value|
        value[:children].last[:children] = []
      }, gridded],
      "namespace child" => [lambda { |value|
        value[:children].last[:id] = "namespace:B"
      }, gridded],
      "no edge" => [->(value) { value[:edges] = [] }, packed],
      "multiple edges" => [lambda { |value|
        value[:edges] << { id: "reverse", sources: ["B"], targets: ["A"] }
      }, packed],
      "self edge" => [lambda { |value|
        value[:edges].first[:targets] = ["A"]
      }, packed],
      "dangling edge" => [lambda { |value|
        value[:edges].first[:targets] = ["C"]
      }, packed],
      "extra child" => [lambda { |value|
        value[:children] << {
          id: "C", width: 100, height: 80, metadata: {}
        }
      }, [[50, 50], [200.0, 50], [350.0, 50]]],
    }.each do |shape, (mutate, expected)|
      it "preserves grid placement for #{shape}" do
        candidate = graph.call
        mutate.call(candidate)
        expect(placed_coordinates(candidate)).to eq(expected)
      end
    end
  end
end
