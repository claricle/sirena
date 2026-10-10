# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Treemap do
  subject(:layout) { described_class.new }

  def nonpositive_scene
    diagram = Sirena::Diagram::Treemap.new
    diagram.title = "No allocation"
    diagram.add_root_node(Sirena::Diagram::TreemapNode.new("Zero", 0))
    diagram.add_root_node(Sirena::Diagram::TreemapNode.new("Debt", -2))
    layout.call(diagram)
  end

  def positive_children
    root = Sirena::Diagram::TreemapNode.new("Root")
    root.add_child(Sirena::Diagram::TreemapNode.new("Positive", 3))
    root.add_child(Sirena::Diagram::TreemapNode.new("Zero", 0))
    root.add_child(Sirena::Diagram::TreemapNode.new("Negative", -1))
    diagram = Sirena::Diagram::Treemap.new
    diagram.add_root_node(root)
    layout.call(diagram).cells.fetch(0).children
  end

  def legacy_cell
    graph = {
      width: 100, height: 80,
      cells: [{
        label: "Extraordinarily long", value: 1.25,
        x: 0, y: 0, width: 35, height: 40,
        css_class: "legacy", depth: 5, children: []
      }],
      class_defs: { "legacy" => "fill: #abc; stroke: #def" }
    }
    described_class.from_graph(graph).cells.fetch(0)
  end

  it "keeps a titled nonpositive hierarchy renderable as an empty canvas" do
    scene = nonpositive_scene
    expect([scene.width, scene.height, scene.cells,
            scene.title.text, scene.title.x])
      .to eq([1000.0, 400.0, [], "No allocation", 500.0])
  end

  it "filters nonpositive descendants without dropping positive siblings" do
    children = positive_children
    expect([children.map { |cell| cell.label.text },
            children.fetch(0).value_label.text]).to eq([["Positive"], "3"])
  end

  it "accepts legacy string styles and formats decimal leaves" do
    cell = legacy_cell
    expect([cell.fill, cell.stroke, cell.label.text, cell.value_label.text])
      .to eq(["#abc", "#def", "Extraordinarily long", "1.2"])
  end
end
