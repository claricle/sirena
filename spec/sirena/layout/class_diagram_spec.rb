# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/class_diagram"

module ClassDiagramLayoutSpecHelpers
  def measured(text, size, monospace: false)
    Sirena::TextMeasurement.measure(
      text, font_size: size, monospace: monospace
    )[:width]
  end

  def parsed(source)
    Sirena::Parser::ClassDiagram.new.parse(source)
  end

  def separator_coordinates(node)
    node.separators.map do |line|
      [line.x1, line.y1, line.x2, line.y2]
    end
  end

  def routed_graph
    nodes = %w[A B].each_with_index.map do |id, index|
      { id: id, x: index * 200, y: 0, width: 100, height: 50,
        metadata: { name: id } }
    end
    section = {
      start_point: { x: 100, y: 25 }, end_point: { x: 200, y: 25 },
      bend_points: [{ x: 150, y: 80 }]
    }
    { children: nodes,
      edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                sections: [section] }] }
  end

  def routed_scene_summary(scene)
    edge = scene.edges.first
    [
      scene.children.flat_map(&:labels).map(&:text),
      [edge.source, edge.target],
      edge.sections.map { |section| section.bend_points.map(&:y) },
    ]
  end

  def multi_section_marker_graph
    graph = routed_graph
    graph[:edges].first[:metadata] = { relationship_type: "inheritance" }
    graph[:edges].first[:sections] = [
      { start_point: { x: 100, y: 25 }, end_point: { x: 150, y: 75 } },
      { start_point: { x: 150, y: 75 }, end_point: { x: 200, y: 25 } },
    ]
    graph
  end
end

RSpec.describe Sirena::Layout::ClassDiagram do
  include ClassDiagramLayoutSpecHelpers

  let(:layout) { described_class.new }
  let(:source) do
    <<~MERMAID
      classDiagram
      class Animal {
        #int age
        +breathe()
      }
      class Dog {
        +bark()
      }
      Dog <|-- Animal : knows
    MERMAID
  end
  let(:diagram) { parsed(source) }
  let(:scene) { layout.call(diagram) }

  it "returns typed final canvas geometry" do
    expect(scene).to be_a(described_class::Scene)
    expect(scene.children).to all(be_a(described_class::Node))
    expect(scene.edges).to all(be_a(described_class::Edge))
    expect([scene.width, scene.height, scene.view_box])
      .to eq([520.0, 214.0, "0 0 520 214"])
  end

  it "positions class nodes through the fallback grid inside layout" do
    expect(scene.children.map { |node| [node.id, node.x, node.y] })
      .to eq([["Animal", 50.0, 50.0], ["Dog", 300.0, 50.0]])
  end

  it "carries final member rows without renderer graph lookups" do
    animal = scene.children.first

    expect(animal.attributes.map(&:text)).to eq(["#int age"])
    expect(animal.method_rows.map(&:text)).to eq(["+breathe()"])
    expect(separator_coordinates(animal))
      .to eq([[50.0, 83.0, 190.0, 83.0], [50.0, 116.0, 190.0, 116.0]])
  end

  it "carries final relationship endpoints, labels, and marker geometry" do
    edge = scene.edges.first
    section = edge.sections.first

    expect([edge.source, edge.target]).to eq(%w[Animal Dog])
    expect([section.start_point.x, section.start_point.y])
      .to eq([190.0, 22.0])
    expect([section.end_point.x, section.end_point.y])
      .to eq([300.0, 151.0])
    expect(edge.labels.map(&:text)).to eq(["knows"])
    expect(edge.markers.map(&:fill)).to eq(["#000000"])
  end

  it "preserves canonical labels and every routed section coordinate" do
    routed = described_class.from_graph(routed_graph)

    expect(routed_scene_summary(routed))
      .to eq([%w[A B], %w[A B], [[80.0]]])
  end

  it "orients routed markers from their adjacent terminal section" do
    edge = described_class.from_graph(multi_section_marker_graph).edges.first
    expected = described_class.triangle_marker(
      { x: 150, y: 75 }, { x: 200, y: 25 }, true
    )

    expect(edge.markers.first.points).to eq(expected.points)
  end

  it "runs Grid once inside layout and not in Engine" do
    allow(Sirena::Layout::Grid).to receive(:apply).and_call_original

    Sirena::Engine.new.render(source)

    expect(Sirena::Layout::Grid).to have_received(:apply).once
  end

  it "uses the legacy empty class canvas upstream" do
    empty_scene = layout.call(parsed("classDiagram\n"))

    expect([empty_scene.width, empty_scene.height, empty_scene.view_box])
      .to eq([880.0, 680.0, "0 0 880 680"])
    expect(empty_scene.children).to be_empty
    expect(empty_scene.edges).to be_empty
  end

  it "lays out shared graph IR identically without mutating the source" do
    before = Marshal.dump(diagram)
    graph = Sirena::Notation::Mermaid::IRAdapters::ClassDiagram.call(diagram)
    from_private_model = Marshal.dump(layout.call(diagram))

    expect([Marshal.dump(layout.call(graph)), Marshal.dump(diagram)])
      .to eq([from_private_model, before])
  end

  it "raises for an invalid diagram" do
    invalid = Sirena::Diagram::ClassDiagram.new
    invalid.relationships << Sirena::Diagram::ClassRelationship.new(
      from_id: "Dog", to_id: "Animal", relationship_type: "inheritance",
    )

    expect { layout.call(invalid) }
      .to raise_error(Sirena::Layout::LayoutError)
  end

  describe "theme-sized text geometry" do
    let(:stereotype_source) do
      "classDiagram\nclass N~T~ <<InternationalOrderProcessor>>\n"
    end

    it "uses the default theme's large and small sizes" do
      node = layout.call(parsed(stereotype_source)).children.first

      expect([node.name.font_size, node.stereotype.font_size])
        .to eq([16.0, 12.0])
      expect(node.stereotype.y).to be < node.name.y
    end

    it "uses high-contrast sizes for measurement and emitted labels" do
      theme = Sirena::Theme::Registry.get(:high_contrast)
      node = layout.call(parsed(stereotype_source), theme: theme).children.first
      expected = measured("<<InternationalOrderProcessor>>", 14) + 20

      expect(node.width).to be_within(0.01).of(expected)
      expect([node.name.font_size, node.stereotype.font_size])
        .to eq([18.0, 14.0])
    end
  end

  describe "member width" do
    {
      "an attribute" => "+#{'i' * 40}",
      "a zero-argument method" => "+#{'i' * 40}()",
      "a method return type" => "+#{'i' * 40}() : String",
      "a typed attribute" => "+String #{'i' * 40}",
    }.each do |label, row|
      it "sizes #{label} from the monospace text drawn" do
        member_scene = layout.call(
          parsed("classDiagram\nclass N {\n  #{row}\n}\n"),
        )
        expected = measured(row, 12, monospace: true) + 20

        expect(member_scene.children.first.width)
          .to be_within(0.01).of(expected)
      end
    end
  end

  it "precomputes a dashed dependency edge without a legacy marker" do
    dependency = layout.call(parsed("classDiagram\nA ..> B\n")).edges.first

    expect([dependency.dashed, dependency.markers]).to eq([true, []])
  end

  describe "name width" do
    it "sizes a class for its large name" do
      name = "InternationalOrderProcessor"
      node = layout.call(parsed("classDiagram\nclass #{name}\n")).children.first

      expect(node.width).to be_within(0.01).of(measured(name, 16) + 20)
    end

    it "sizes a stereotype on its own small-font line" do
      stereotype = "InternationalOrderProcessor"
      node = layout.call(
        parsed("classDiagram\nclass N <<#{stereotype}>>\n"),
      ).children.first

      expect(node.width)
        .to be_within(0.01).of(measured("<<#{stereotype}>>", 12) + 20)
    end
  end
end
