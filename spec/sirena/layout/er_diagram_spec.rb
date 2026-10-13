# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ErDiagram, :aggregate_failures do
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
      value.entities << Sirena::Diagram::ErEntity.new(
        id: "ORDER", name: "ORDER",
      )
      value.relationships << Sirena::Diagram::ErRelationship.new(
        from_id: "CUSTOMER", to_id: "ORDER",
        relationship_type: "non-identifying",
        cardinality_from: "one", cardinality_to: "zero_or_more",
        label: "places"
      )
    end
  end

  def ir_customer
    Sirena::Diagram::ErEntity.new(
      id: "CUSTOMER", name: "Customer", classes: %w[primary audited],
      attributes: [Sirena::Diagram::ErAttribute.new(
        name: "id", attribute_type: "int", key_type: "PK", note: "generated",
      )]
    )
  end

  def ir_order
    Sirena::Diagram::ErEntity.new(
      id: "ORDER", name: "Order", classes: ["audited"],
      attributes: [Sirena::Diagram::ErAttribute.new(
        name: "customer_id", attribute_type: "int", key_type: "FK",
      )]
    )
  end

  def ir_relationships
    [Sirena::Diagram::ErRelationship.new(
      from_id: "CUSTOMER", to_id: "ORDER", relationship_type: "identifying",
      cardinality_from: "one", cardinality_to: "zero_or_more",
      label: "places"
    )]
  end

  def ir_equivalence_diagram
    value = Sirena::Diagram::ErDiagram.new(
      id: "commerce", title: "Commerce model", direction: "LR",
      theme: "forest", entities: [ir_customer, ir_order],
      relationships: ir_relationships
    )
    value.add_class_def("primary", "fill:red")
    value.add_class_def("audited", "stroke:blue")
    value
  end

  def inputs_unchanged_after_layout?
    private_diagram = ir_equivalence_diagram
    graph = Sirena::Notation::Mermaid::IRAdapters::ErDiagram
      .call(private_diagram)
    before = [Marshal.dump(private_diagram), Marshal.dump(graph)]
    layout.call(private_diagram)
    layout.call(graph)
    [Marshal.dump(private_diagram), Marshal.dump(graph)] == before
  end

  describe "#call" do
    it "returns final typed scene geometry" do
      scene = layout.call(diagram)

      expect(scene).to be_a(described_class::Scene)
      expect(scene.children).to all(be_a(described_class::Node))
      expect(scene.edges).to all(be_a(described_class::Edge))
      expect(scene.view_box).to eq("0 0 #{scene.width} #{scene.height}")
    end

    it "closes the canvas 8px past the farthest entity edge, as mmdc does" do
      scene = layout.call(diagram)
      right = scene.children.map { |node| node.x + node.width }.max
      bottom = scene.children.map { |node| node.y + node.height }.max

      expect([scene.width, scene.height]).to eq([right + 8, bottom + 8])
    end

    it "lays out direct graph IR byte-identically to its private model" do
      private_diagram = ir_equivalence_diagram
      graph = Sirena::Notation::Mermaid::IRAdapters::ErDiagram
        .call(private_diagram)

      expect(Marshal.dump(layout.call(graph)))
        .to eq(Marshal.dump(layout.call(private_diagram)))
    end

    it "does not mutate either private or graph input during layout" do
      expect(inputs_unchanged_after_layout?).to be(true)
    end

    # mmdc lays this diagram out as CUSTOMER 172.67 x 128.25 centred at
    # (94.336, 72.125) and ORDER 100 x 84 centred at (94.336, 279.25),
    # inside a 188.67 x 329.25 viewBox.
    context "when placing the sample diagram" do
      let(:scene) { layout.call(diagram) }
      let(:customer) { scene.children.first }
      let(:order) { scene.children[1] }

      it "places the CUSTOMER entity where mmdc does" do
        expect([customer.x, customer.y, customer.width, customer.height])
          .to match([be_within(0.1).of(8), 8,
                     be_within(0.1).of(172.67), 128.25])
      end

      it "places the ORDER entity where mmdc does" do
        expect([order.x, order.y, order.width, order.height])
          .to match([be_within(0.1).of(44.336), 237.25, 100, 84])
      end

      it "sizes the canvas where mmdc does" do
        expect([scene.width, scene.height])
          .to match([be_within(0.1).of(188.67), 329.25])
      end

      it "centres the name by mmdc's layout" do
        expect(customer.labels.first.x)
          .to be_within(0.1).of(customer.x + (customer.width / 2))
      end

      it "lists the attribute rows in order" do
        expect(customer.attributes.map(&:text))
          .to eq(["PK int id", "string name"])
      end

      it "steps attribute rows by mmdc's row height" do
        expect(customer.attributes.map(&:y).each_cons(2).map { |a, b| b - a })
          .to eq([42.75])
      end
    end

    context "with the canonical relationship" do
      let(:edge) { layout.call(diagram).edges.first }
      let(:section) { edge.sections.first }

      it "names the relationship's source and target" do
        expect([edge.source, edge.target]).to eq(%w[CUSTOMER ORDER])
      end

      it "includes a section with point ends and no bend points" do
        expect([section.start_point, section.end_point])
          .to all(be_a(described_class::Point))
        expect(section.bend_points).to eq([])
      end

      it "includes the source marker line" do
        expect(edge.source_marker.lines.length).to eq(1)
      end

      it "includes the target marker circle and lines" do
        expect([edge.target_marker.circles.length,
                edge.target_marker.lines.length]).to eq([1, 3])
      end
    end

    context "with an attribute that carries a note" do
      let(:attribute) { layout.call(diagram).children.first.attributes.first }

      before { diagram.entities.first.attributes.first.note = "NN" }

      it "preserves the attribute's name, type and key" do
        expect([attribute.name, attribute.attribute_type, attribute.key_type])
          .to eq(%w[id int PK])
      end

      it "preserves the optional note" do
        expect([attribute.note, attribute.text]).to eq(["NN", "PK int id NN"])
      end
    end

    it "widens the entity box to fit a long attribute note" do
      narrow = layout.call(diagram).children.first.width
      diagram.entities.first.attributes.first.note =
        "a much longer note than the name alone"

      expect(layout.call(diagram).children.first.width).to be > narrow
    end

    context "with one entity holding a 40-character attribute name" do
      let(:narrow_diagram) do
        entity = Sirena::Diagram::ErEntity.new(id: "NARROW", name: "NARROW")
        entity.attributes << Sirena::Diagram::ErAttribute.new(
          name: "i" * 40, attribute_type: "string",
        )
        Sirena::Diagram::ErDiagram.new.tap { |value| value.entities << entity }
      end

      # mmdc draws this diagram in a 288.875 x 101.5 viewBox, 8px margin
      # each side.
      it "sizes an entity to mmdc's Trebuchet measure of its widest cell" do
        expect(layout.call(narrow_diagram).children.first.width)
          .to be_within(0.5).of(288.875 - 16)
      end
    end

    context "with a 40-W entity name under two themes" do
      let(:ordinary) do
        layout.call(diagram, theme: Sirena::Theme::Registry.get(:default))
      end
      let(:contrast_theme) { Sirena::Theme::Registry.get(:high_contrast) }
      let(:contrast) { layout.call(diagram, theme: contrast_theme) }

      before { diagram.entities.first.name = "W" * 40 }

      it "labels the entity at the contrast theme's large font size" do
        expect(contrast.children.first.labels.first.font_size)
          .to eq(contrast_theme.typography.font_size_large)
      end

      # mmdc draws a 40-W entity 595.3125 wide.
      it "sizes entity boxes the same under every theme, as mmdc does" do
        expect([ordinary, contrast].map { |scene| scene.children.first.width })
          .to all(be_within(0.5).of(595.3125))
      end
    end

    context "with assigned classes and declarations" do
      let(:scene) { layout.call(diagram) }

      before do
        diagram.entities.first.classes.push("first", "second", "first")
        diagram.add_class_def("first", "fill:red")
        diagram.add_class_def("second", "stroke:blue")
      end

      it "preserves the assigned classes in source order" do
        expect(scene.children.first.classes).to eq(%w[first second first])
      end

      it "preserves the declarations in source order" do
        expect(scene.class_defs.map { |item| [item.name, item.declaration] })
          .to eq([["first", "fill:red"], ["second", "stroke:blue"]])
      end
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
