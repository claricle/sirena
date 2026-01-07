# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/mindmap"

RSpec.describe Sirena::Parser::MindmapParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with simple root" do
      it "parses a simple root node" do
        source = <<~MERMAID
          mindmap
            root
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Mindmap)
        expect(diagram.root).not_to be_nil
        expect(diagram.root.content).to eq("root")
        expect(diagram.root.level).to eq(0)
      end

      it "parses a root with indentation" do
        source = <<~MERMAID
          mindmap
              root
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root).not_to be_nil
        expect(diagram.root.content).to eq("root")
      end
    end

    context "with hierarchical structure" do
      it "parses a simple hierarchy" do
        source = <<~MERMAID
          mindmap
              root
                child1
                child2
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.children.size).to eq(2)
        expect(diagram.root.children.map(&:content)).to eq(["child1", "child2"])
      end

      it "parses a deeper hierarchy" do
        source = <<~MERMAID
          mindmap
              root
                child1
                  leaf1
                child2
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.children.size).to eq(2)
        expect(diagram.root.children.first.children.size).to eq(1)
        expect(diagram.root.children.first.children.first.content).to eq("leaf1")
      end
    end

    context "with node shapes" do
      it "parses circle nodes" do
        source = <<~MERMAID
          mindmap
           root((the root))
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("circle")
        expect(diagram.root.content).to eq("the root")
      end

      it "parses cloud nodes" do
        source = <<~MERMAID
          mindmap
           root)the root(
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("cloud")
        expect(diagram.root.content).to eq("the root")
      end

      it "parses bang nodes" do
        source = <<~MERMAID
          mindmap
           root))the root((
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("bang")
        expect(diagram.root.content).to eq("the root")
      end

      it "parses hexagon nodes" do
        source = <<~MERMAID
          mindmap
           root{{the root}}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("hexagon")
        expect(diagram.root.content).to eq("the root")
      end

      it "parses square nodes" do
        source = <<~MERMAID
          mindmap
              root[The root]
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("square")
        expect(diagram.root.content).to eq("The root")
      end
    end

    context "with icons" do
      it "parses nodes with icons" do
        source = <<~MERMAID
          mindmap
              root[The root]
              ::icon(bomb)
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.icon).to eq("bomb")
      end

      it "parses multiple nodes with icons" do
        source = <<~MERMAID
          mindmap
            root((mindmap))
              Origins
                ::icon(fa fa-book)
        MERMAID

        diagram = parser.parse(source)
        child = diagram.root.children.first
        expect(child.icon).to eq("fa fa-book")
      end
    end

    context "with classes" do
      it "parses nodes with classes" do
        source = <<~MERMAID
          mindmap
              root[The root]
              :::m-4 p-8
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.classes).to include("m-4", "p-8")
      end

      it "parses nodes with both classes and icons" do
        source = <<~MERMAID
          mindmap
              root[The root]
              :::m-4 p-8
              ::icon(bomb)
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.classes).to include("m-4", "p-8")
        expect(diagram.root.icon).to eq("bomb")
      end
    end

    context "with complex structures" do
      it "parses a full example mindmap" do
        source = <<~MERMAID
          mindmap
            root((mindmap))
              Origins
                Long history
                ::icon(fa fa-book)
                Popularisation
                  British popular psychology author Tony Buzan
              Research
                On effectiveness<br/>and features
                On Automatic creation
                  Uses
                      Creative techniques
                      Strategic planning
                      Argument mapping
              Tools
                Pen and paper
                Mermaid
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root).not_to be_nil
        expect(diagram.root.content).to eq("mindmap")
        expect(diagram.root.shape).to eq("circle")
        expect(diagram.root.children.size).to eq(3)

        origins = diagram.root.children[0]
        expect(origins.content).to eq("Origins")
        expect(origins.children.size).to eq(2)
      end
    end
  end
end