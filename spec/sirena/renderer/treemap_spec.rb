# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/treemap"
require "sirena/diagram/treemap"

RSpec.describe Sirena::Renderer::Treemap, :aggregate_failures do
  let(:diagram) { Sirena::Diagram::Treemap.new }
  let(:transform) { Sirena::Layout::Treemap.new }
  let(:renderer) { described_class.new }

  let(:svg) { renderer.render(transform.to_graph(diagram)).to_xml }

  def add_root_with_children(children, name = "Root")
    parent = Sirena::Diagram::TreemapNode.new(name)
    children.each do |child|
      child = Sirena::Diagram::TreemapNode.new(*child) if child.is_a?(Array)
      parent.add_child(child)
    end
    diagram.add_root_node(parent)
  end

  def add_root_nodes(children)
    children.each { |args| diagram.add_root_node(Sirena::Diagram::TreemapNode.new(*args)) }
  end

  describe "#render" do
    context "with basic treemap" do
      it "renders simple treemap with one node as a Document" do
        add_root_with_children([["Child", 100]])

        expect(renderer.render(transform.to_graph(diagram)))
          .to be_a(Sirena::Svg::Document)
      end

      it "renders simple treemap with one node" do
        add_root_with_children([["Child", 100]])

        expect(svg).to include("<svg", "</svg>", "Root", "Child")
      end

      it "renders with title" do
        diagram.title = "My Treemap"
        diagram.add_root_node(Sirena::Diagram::TreemapNode.new("Root", 100))

        expect(svg).to include("My Treemap")
      end
    end

    context "with multiple nodes" do
      it "renders multiple root nodes" do
        add_root_with_children([["Leaf 1", 50]], "Section 1")
        add_root_with_children([["Leaf 2", 30]], "Section 2")

        expect(svg).to include("Section 1", "Section 2", "Leaf 1", "Leaf 2")
      end

      it "renders nested hierarchy" do
        level2 = Sirena::Diagram::TreemapNode.new("Level 2")
        level2.add_child(Sirena::Diagram::TreemapNode.new("Level 3", 100))
        add_root_with_children([level2], "Level 1")

        expect(svg).to include("Level 1", "Level 2", "Level 3")
      end
    end

    context "with styling" do
      it "applies different colors to different depth levels" do
        add_root_with_children([["Child1", 50], ["Child2", 50]])

        # Should have colored rectangles
        expect(svg).to include("<rect", "fill=")
      end

      it "applies CSS class styles when defined" do
        diagram.add_class_def("important", "fill:#f96,stroke:#333")
        important = Sirena::Diagram::TreemapNode.new("Important", 100)
        important.css_class = "important"
        add_root_with_children([important])

        # Should use the custom fill color
        expect(svg).to include("#f96")
      end
    end

    context "with values" do
      it "displays values for leaf nodes" do
        add_root_with_children([["Leaf", 123]])

        expect(svg).to include("123")
      end

      it "formats decimal values" do
        add_root_with_children([["Leaf", 123.7]])

        expect(svg).to include("123.7")
      end

      it "retains zero root nodes and skips negative ones" do
        add_root_nodes([["Positive", 10], ["Zero", 0], ["Negative", -2]])

        layout = transform.to_graph(diagram)

        expect(layout.cells.map { |cell| cell.label.text })
          .to eq(%w[Positive Zero])
      end

      it "retains valueless children and skips negative ones" do
        add_root_with_children([["Positive", 10], ["Valueless"],
                                ["Negative", -2]])

        children = transform.to_graph(diagram).cells.first.children

        expect(children.map { |cell| cell.label.text })
          .to eq(%w[Positive Valueless])
      end
    end

    context "with empty diagram" do
      it "renders empty treemap gracefully" do
        expect(svg).to include("<svg", "</svg>")
      end
    end
  end
end
