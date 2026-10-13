# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ClassDiagram Integration", :aggregate_failures do
  describe "complete class diagram pipeline" do
    let(:diagram) { Sirena::Parser::ClassDiagram.new.parse(source) }
    let(:scene) { Sirena::Layout::ClassDiagram.new.call(diagram) }
    let(:svg) { Sirena::Renderer::ClassDiagram.new.render(scene) }

    context "with a simple class diagram" do
      let(:source) { "classDiagram\nAnimal <|-- Dog" }

      it "parses a valid ClassDiagram" do
        expect(diagram).to be_a(Sirena::Diagram::ClassDiagram)
        expect(diagram.valid?).to be true
      end

      it "transforms to a Scene with both classes and the edge" do
        expect(scene).to be_a(Sirena::Layout::ClassDiagram::Scene)
        expect(scene.children.length).to eq(2)
        expect(scene.edges.length).to eq(1)
      end

      it "renders a non-empty SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
        expect(svg.children).not_to be_empty
      end
    end

    context "with multiple relationship types" do
      let(:source) do
        <<~MERMAID
          classDiagram
          Animal <|-- Dog
          Car *-- Engine
          Team o-- Player
          Student -- Course
        MERMAID
      end

      it "parses every entity and relationship" do
        expect(diagram.entities.length).to eq(8)
        expect(diagram.relationships.length).to eq(4)
      end

      it "classifies the relationship kinds" do
        expect(diagram.inheritance_relationships.length).to eq(1)
        expect(diagram.composition_relationships.length).to eq(1)
        expect(diagram.aggregation_relationships.length).to eq(1)
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with classes holding attributes and methods" do
      let(:source) do
        <<~MERMAID
          classDiagram
          class Animal {
            +name: string
            #age: int
            +breathe()
            +move(x: int, y: int): void
          }
          class Dog {
            +bark(): void
          }
          Animal <|-- Dog
        MERMAID
      end

      it "parses the attributes and methods of Animal" do
        animal = diagram.find_entity("Animal")

        expect(animal).not_to be_nil
        expect(animal.attributes.length).to eq(2)
        expect(animal.class_methods.length).to eq(2)
      end

      it "parses the methods of Dog" do
        dog = diagram.find_entity("Dog")

        expect(dog).not_to be_nil
        expect(dog.class_methods.length).to eq(1)
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with stereotypes" do
      let(:source) do
        <<~MERMAID
          classDiagram
          class Drawable <<interface>> {
            +draw(): void
          }
          class Shape <<abstract>> {
            +area(): float
          }
          Drawable <|-- Shape
        MERMAID
      end

      it "marks Drawable as an interface" do
        expect(diagram.find_entity("Drawable").interface?).to be true
      end

      it "marks Shape as abstract" do
        expect(diagram.find_entity("Shape").abstract?).to be true
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with an LR diagram" do
      let(:source) { "classDiagram LR\nAnimal <|-- Dog" }

      it "parses the direction" do
        expect(diagram.direction).to eq("LR")
      end

      it "converts to a positioned Scene" do
        expect([scene.class, scene.children.map(&:x)])
          .to eq([Sirena::Layout::ClassDiagram::Scene, [50.0, 175.136]])
      end
    end

    context "with cardinality labels" do
      let(:source) do
        "classDiagram\nStudent \"1\" -- \"0..*\" Course : enrolls in"
      end
      let(:edge) { scene.edges.first }

      it "parses the cardinalities and label" do
        rel = diagram.relationships.first

        expect(rel.source_cardinality).to eq("1")
        expect(rel.target_cardinality).to eq("0..*")
        expect(rel.label).to eq("enrolls in")
      end

      it "transforms every label onto the edge" do
        expect(edge.labels.map(&:text))
          .to contain_exactly("enrolls in", "1", "0..*")
      end

      it "anchors each label as mmdc does" do
        anchors = edge.labels.to_h { |label| [label.text, label.text_anchor] }

        expect(anchors).to eq("enrolls in" => "middle", "1" => nil,
                              "0..*" => "end")
      end
    end
  end

  describe "DiagramRegistry integration" do
    it "has class_diagram registered" do
      expect(Sirena::DiagramRegistry.registered?(:class_diagram)).to be true
    end

    it "retrieves class diagram handlers" do
      handlers = Sirena::DiagramRegistry.get(:class_diagram)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(Sirena::Parser::ClassDiagram)
      expect(handlers[:transform]).to eq(Sirena::Layout::ClassDiagram)
      expect(handlers[:renderer]).to eq(Sirena::Renderer::ClassDiagram)
    end
  end
end
