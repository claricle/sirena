# frozen_string_literal: true

require "spec_helper"

module ClassDiagramLayoutSpecHelpers
  def measured(text, size)
    Sirena::TextMeasurement.measure(text, font_size: size)[:width]
  end
end

RSpec.describe Sirena::Layout::ClassDiagram do
  include ClassDiagramLayoutSpecHelpers

  let(:transform) { described_class.new }

  describe "#to_graph" do
    let(:dangling_relationship) do
      Sirena::Diagram::ClassRelationship.new(from_id: "Dog", to_id: "Animal",
                                             relationship_type: "inheritance")
    end

    let(:diagram) do
      Sirena::Diagram::ClassDiagram.new(direction: "TB").tap do |d|
        d.entities << Sirena::Diagram::ClassEntity.new(
          id: "Animal",
          name: "Animal",
        ).tap do |entity|
          entity.attributes << Sirena::Diagram::ClassAttribute.new(
            name: "age",
            type: "int",
            visibility: "protected",
          )
          entity.class_methods << Sirena::Diagram::ClassMethod.new(
            name: "breathe",
            visibility: "public",
          )
        end
        d.entities << Sirena::Diagram::ClassEntity.new(
          id: "Dog",
          name: "Dog",
        ).tap do |entity|
          entity.class_methods << Sirena::Diagram::ClassMethod.new(
            name: "bark",
            visibility: "public",
          )
        end
        d.relationships << Sirena::Diagram::ClassRelationship.new(
          from_id: "Dog",
          to_id: "Animal",
          relationship_type: "inheritance",
        )
      end
    end

    it "converts diagram to graph structure" do
      graph = transform.to_graph(diagram)

      expect(graph).to be_a(Hash)
      expect(graph[:id]).to eq("class_diagram")
      expect(graph[:children]).to be_an(Array)
      expect(graph[:edges]).to be_an(Array)
      expect(graph[:layoutOptions]).to be_a(Hash)
    end

    it "creates entities with dimensions" do
      graph = transform.to_graph(diagram)

      expect(graph[:children].length).to eq(2)

      animal = graph[:children].find { |n| n[:id] == "Animal" }
      expect(animal).not_to be_nil
      expect(animal[:width]).to be > 0
      expect(animal[:height]).to be > 0
      expect(animal[:metadata][:name]).to eq("Animal")
      expect(animal[:metadata][:attributes]).to be_an(Array)
      expect(animal[:metadata][:methods]).to be_an(Array)
    end

    it "includes attributes metadata" do
      graph = transform.to_graph(diagram)

      animal = graph[:children].find { |n| n[:id] == "Animal" }
      attributes = animal[:metadata][:attributes]

      expect(attributes.length).to eq(1)
      expect(attributes.first[:name]).to eq("age")
      expect(attributes.first[:type]).to eq("int")
      expect(attributes.first[:visibility]).to eq("protected")
    end

    it "includes methods metadata" do
      graph = transform.to_graph(diagram)

      animal = graph[:children].find { |n| n[:id] == "Animal" }
      methods = animal[:metadata][:methods]

      expect(methods.length).to eq(1)
      expect(methods.first[:name]).to eq("breathe")
      expect(methods.first[:visibility]).to eq("public")
    end

    it "creates relationships with metadata" do
      graph = transform.to_graph(diagram)

      expect(graph[:edges].length).to eq(1)

      edge = graph[:edges].first
      expect(edge[:sources]).to eq(["Dog"])
      expect(edge[:targets]).to eq(["Animal"])
      expect(edge[:metadata][:relationship_type]).to eq("inheritance")
    end

    it "sets layout options based on direction" do
      graph = transform.to_graph(diagram)

      options = graph[:layoutOptions]
      expect(options["elk.algorithm"]).to eq("layered")
      expect(options["elk.direction"]).to eq("DOWN")
    end

    it "converts LR direction to RIGHT layout" do
      diagram.direction = "LR"
      graph = transform.to_graph(diagram)

      expect(graph[:layoutOptions]["elk.direction"]).to eq("RIGHT")
    end

    it "handles entities with stereotypes" do
      diagram.entities.first.stereotype = "interface"
      graph = transform.to_graph(diagram)

      animal = graph[:children].find { |n| n[:id] == "Animal" }
      expect(animal[:metadata][:stereotype]).to eq("interface")
    end

    it "raises error for invalid diagram" do
      invalid_diagram = Sirena::Diagram::ClassDiagram.new
      invalid_diagram.relationships << dangling_relationship

      expect { transform.to_graph(invalid_diagram) }
        .to raise_error(Sirena::Layout::LayoutError)
    end
  end

  # Narrow glyphs: the monospace width (0.6 em each) and the proportional
  # width (about 0.22 em each) differ by a factor of nearly three, so a
  # box sized with the wrong family cannot pass.
  describe "member width" do
    let(:name) { "i" * 40 }
    let(:entity) { Sirena::Diagram::ClassEntity.new(id: "N", name: "N") }
    let(:narrow_diagram) do
      Sirena::Diagram::ClassDiagram.new(direction: "TB").tap do |d|
        d.entities << entity
      end
    end
    let(:drawn_width) do
      Sirena::TextMeasurement.measure(
        "+ #{name}", font_size: 12, monospace: true
      )[:width] + 20
    end

    it "sizes an attribute compartment in the monospace width drawn" do
      entity.attributes << Sirena::Diagram::ClassAttribute.new(
        name: name, visibility: "public",
      )

      node = transform.to_graph(narrow_diagram)[:children].first
      expect(node[:width]).to be_within(0.01).of(drawn_width)
    end

    it "adds no type separator for an attribute with an empty type" do
      entity.attributes << Sirena::Diagram::ClassAttribute.new(
        name: name, visibility: "public", type: "",
      )

      node = transform.to_graph(narrow_diagram)[:children].first
      expect(node[:width]).to be_within(0.01).of(drawn_width)
    end

    it "sizes a method compartment in the monospace width drawn" do
      entity.class_methods << Sirena::Diagram::ClassMethod.new(
        name: name, visibility: "public",
      )

      node = transform.to_graph(narrow_diagram)[:children].first
      expect(node[:width]).to be_within(0.01).of(drawn_width)
    end
  end

  # The box must fit the row text exactly as the renderer builds it: "()" for
  # an empty parameter list, ": " before a return or attribute type.
  describe "member row text" do
    name = "i" * 40
    {
      "a zero-argument method" => ["+#{name}()", "+ #{name}()"],
      "a method with a return type" =>
        ["+#{name}() String", "+ #{name}(): String"],
      "an attribute with a type" => ["+String #{name}", "+ #{name}: String"],
    }.each do |label, (row, drawn)|
      context "with #{label}" do
        let(:source) { "classDiagram\nclass N {\n  #{row}\n}\n" }
        let(:node) do
          model = Sirena::Parser::ClassDiagram.new.parse(source)
          transform.to_graph(model)[:children].first
        end

        it "sizes the box from the text drawn" do
          drawn_width = Sirena::TextMeasurement.measure(
            drawn, font_size: 12, monospace: true
          )[:width]

          expect(node[:width]).to be_within(0.01).of(drawn_width + 20)
        end
      end
    end
  end

  # The renderer draws the name at 16 and the stereotype at 11, each as its
  # own line, so the box fits the wider of the two measured at those sizes.
  describe "name width" do
    let(:entity) do
      Sirena::Diagram::ClassEntity.new(
        id: "N", name: "InternationalOrderProcessor",
      )
    end
    let(:name_diagram) do
      Sirena::Diagram::ClassDiagram.new(direction: "TB").tap do |d|
        d.entities << entity
      end
    end
    let(:node) { transform.to_graph(name_diagram)[:children].first }

    it "sizes the box for the name at the size it is drawn" do
      expect(node[:width]).to be_within(0.01).of(measured(entity.name, 16) + 20)
    end

    it "measures a stereotype on its own line at its own size" do
      entity.name = "N"
      entity.stereotype = "InternationalOrderProcessor"
      stereotype = "<<#{entity.stereotype}>>"

      expect(node[:width]).to be_within(0.01).of(measured(stereotype, 11) + 20)
    end
  end
end
