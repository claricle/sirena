# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  let(:case_path) do
    File.expand_path(
      "../../mermaid/class_diagram/" \
      "classdiagram_elk_v3_spec-76ab7ba5.mmd",
      __dir__,
    )
  end
  let(:source) { File.read(case_path) }
  let(:diagram) { Sirena::Parser::ClassDiagram.new.parse(source) }
  let(:scene) { described_class.new.call(diagram) }
  let(:nodes) { scene.children.to_h { |node| [node.id, node] } }
  let(:source_node) { nodes.fetch("C1") }
  let(:target_node) { nodes.fetch("C2") }
  let(:section) { scene.edges.fetch(0).sections.fetch(0) }

  it "places the connected pair in a centered vertical lane" do
    source_center = source_node.x + (source_node.width / 2)
    target_center = target_node.x + (target_node.width / 2)
    vertical_gap = target_node.y - source_node.y - source_node.height

    expect([source_node.x, source_node.y, source_center])
      .to eq([Sirena::Layout::Grid::MARGIN, 50.0, target_center])
    expect(vertical_gap).to eq(Sirena::Layout::ClassCellPlacement::CELL_GAP)
  end

  it "routes the source-to-target edge vertically between the boxes" do
    expect(section.end_point.x).to eq(section.start_point.x)
    expect([section.start_point.y, section.end_point.y])
      .to eq([source_node.y + source_node.height, target_node.y])
  end

  describe Sirena::Layout::ClassCellPlacement, :aggregate_failures do
    it "keeps caller-selected coordinates for a matching pair" do
      children = [
        { id: "A", width: 100, height: 80, metadata: {}, x: 7 },
        { id: "B", width: 100, height: 80, metadata: {}, y: 13 },
      ]
      candidate = {
        children: children,
        edges: [{ id: "edge", sources: ["A"], targets: ["B"] }],
        layoutOptions: { "elk.direction" => "DOWN" },
      }

      described_class.apply(candidate)
      expect(children.map { |child| [child[:x], child[:y]] })
        .to eq([[7, 50], [50.0, 13]])
    end

    it "orders by edge direction and centers against the wider box" do
      children = [
        { id: "B", width: 120, height: 80, metadata: {} },
        { id: "A", width: 80, height: 80, metadata: {} },
      ]
      candidate = {
        children: children,
        edges: [{ id: "edge", sources: ["A"], targets: ["B"] }],
        layoutOptions: { "elk.direction" => "DOWN" },
      }

      described_class.apply(candidate)
      positions = children.to_h { |child| [child[:id], [child[:x], child[:y]]] }

      expect(positions).to eq("A" => [70.0, 50], "B" => [50.0, 180.0])
    end

    it "preserves grid placement outside the exact connected-pair shape" do
      graph = lambda do
        {
          children: [
            { id: "A", width: 100, height: 80, metadata: {} },
            { id: "B", width: 100, height: 80, metadata: {} },
          ],
          edges: [{ id: "edge", sources: ["A"], targets: ["B"] }],
          layoutOptions: { "elk.direction" => "DOWN" },
        }
      end
      packed = [[50, 50], [200.0, 50]]
      gridded = [[50, 50], [300, 50]]
      variants = {
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
      }

      variants.each do |shape, (mutate, expected)|
        candidate = graph.call
        mutate.call(candidate)
        described_class.apply(candidate)
        positions = candidate[:children].map { |child| [child[:x], child[:y]] }

        expect(positions).to eq(expected), shape
      end
    end
  end
end
