# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ErDiagram do
  let(:layout) { described_class.new }
  let(:diagram) do
    Sirena::Diagram::ErDiagram.new.tap do |value|
      customer = Sirena::Diagram::ErEntity.new(id: "CUSTOMER", name: "CUSTOMER")
      customer.attributes << Sirena::Diagram::ErAttribute.new(
        name: "id", attribute_type: "int", key_type: "PK",
      )
      customer.attributes << Sirena::Diagram::ErAttribute.new(
        name: "name", attribute_type: "string",
      )
      value.entities << customer
      value.entities << Sirena::Diagram::ErEntity.new(id: "ORDER", name: "ORDER")
      value.relationships << Sirena::Diagram::ErRelationship.new(
        from_id: "CUSTOMER", to_id: "ORDER",
        relationship_type: "non-identifying",
        cardinality_from: "one", cardinality_to: "zero_or_more",
        label: "places"
      )
    end
  end

  describe "#call" do
    it "returns final typed scene geometry" do
      scene = layout.call(diagram)

      expect(scene).to be_a(described_class::Scene)
      expect(scene.children).to all(be_a(described_class::Node))
      expect(scene.edges).to all(be_a(described_class::Edge))
      expect([scene.width, scene.height, scene.view_box])
        .to eq([550.0, 210.0, "0 0 550 210"])
    end

    it "places entities and their text in final canvas coordinates" do
      customer = layout.call(diagram).children.find { |node| node.id == "CUSTOMER" }

      expect([customer.x, customer.y, customer.width, customer.height])
        .to eq([50.0, 50.0, 170.0, 80.0])
      expect([customer.labels.first.x, customer.labels.first.y])
        .to eq([135.0, 76.0])
      expect(customer.attributes.map(&:text)).to eq(["PK int id", "string name"])
      expect(customer.attributes.map { |row| [row.x, row.y] })
        .to eq([[60.0, 116.0], [60.0, 134.0]])
    end

    it "includes canonical relationship sections and markers" do
      edge = layout.call(diagram).edges.first
      section = edge.sections.first

      expect([edge.source, edge.target]).to eq(%w[CUSTOMER ORDER])
      expect(section.start_point).to be_a(described_class::Point)
      expect(section.end_point).to be_a(described_class::Point)
      expect(section.bend_points).to eq([])
      expect(edge.source_marker.lines.length).to eq(1)
      expect(edge.target_marker.circles.length).to eq(1)
      expect(edge.target_marker.lines.length).to eq(3)
    end

    it "preserves attributes and their optional note" do
      diagram.entities.first.attributes.first.note = "NN"
      attribute = layout.call(diagram).children.first.attributes.first

      expect([attribute.name, attribute.attribute_type, attribute.key_type])
        .to eq(%w[id int PK])
      expect([attribute.note, attribute.text]).to eq(["NN", "PK int id NN"])
    end

    it "widens the entity box to fit a long attribute note" do
      narrow = layout.call(diagram).children.first.width
      diagram.entities.first.attributes.first.note =
        "a much longer note than the name alone"

      expect(layout.call(diagram).children.first.width).to be > narrow
    end

    it "uses monospace theme sizing for attribute width" do
      name = "i" * 40
      entity = Sirena::Diagram::ErEntity.new(id: "NARROW", name: "N")
      entity.attributes << Sirena::Diagram::ErAttribute.new(name: name)
      narrow = Sirena::Diagram::ErDiagram.new.tap { |value| value.entities << entity }
      node = layout.call(narrow).children.first
      font_size = Sirena::Theme::Registry.get(:default).typography.font_size_small
      drawn = Sirena::TextMeasurement.measure(
        name, font_size: font_size, monospace: true
      )[:width] + 20

      expect(node.width).to be_within(0.01).of(drawn)
    end

    it "sizes and positions text from the injected theme" do
      diagram.entities.first.name = "W" * 40
      ordinary = layout.call(diagram, theme: Sirena::Theme::Registry.get(:default))
      contrast = layout.call(diagram, theme: Sirena::Theme::Registry.get(:high_contrast))

      expect(contrast.children.first.labels.first.font_size)
        .to eq(Sirena::Theme::Registry.get(:high_contrast).typography.font_size_large)
      expect(contrast.children.first.width).not_to eq(ordinary.children.first.width)
    end

    it "preserves assigned classes and declarations in source order" do
      diagram.entities.first.classes.push("first", "second", "first")
      diagram.add_class_def("first", "fill:red")
      diagram.add_class_def("second", "stroke:blue")
      scene = layout.call(diagram)

      expect(scene.children.first.classes).to eq(%w[first second first])
      expect(scene.class_defs.map { |item| [item.name, item.declaration] })
        .to eq([["first", "fill:red"], ["second", "stroke:blue"]])
    end

    it "returns the mermaid-compatible empty canvas" do
      scene = layout.call(Sirena::Diagram::ErDiagram.new)

      expect([scene.width, scene.height, scene.view_box])
        .to eq([16.0, 16.0, "0 0 16 16"])
      expect([scene.children, scene.edges]).to eq([[], []])
    end

    it "raises for an entity missing its name" do
      invalid = Sirena::Diagram::ErDiagram.new.tap do |value|
        value.entities << Sirena::Diagram::ErEntity.new(id: "CUSTOMER")
      end

      expect { layout.call(invalid) }.to raise_error(Sirena::Layout::LayoutError)
    end
  end
end
