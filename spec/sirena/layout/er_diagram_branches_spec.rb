# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ErDiagram do
  let(:children) do
    [
      { id: "A", x: 0, y: 0, width: 100, height: 60 },
      { id: "B", x: 200, y: 0, width: 100, height: 60 },
    ]
  end

  def relationship(id, extra = {})
    {
      id: id, sources: ["A"], targets: ["B"],
      labels: [{ text: id }],
      metadata: {
        cardinality_from: "one",
        cardinality_to: "zero_or_more",
      }
    }.merge(extra)
  end

  it "accepts fallback, snake-case, camel-case, and typed sections" do
    typed = described_class::Section.new(
      start_point: described_class::Point.new(x: 100, y: 15),
      end_point: described_class::Point.new(x: 200, y: 15),
    )
    snake = {
      start_point: { x: 100, y: 20 }, end_point: { x: 200, y: 20 },
      bend_points: [{ x: 150, y: 30 }]
    }
    camel = {
      "startPoint" => { x: 100, y: 25 },
      "endPoint" => { x: 200, y: 25 },
      "bendPoints" => [{ x: 150, y: 35 }],
    }
    edges = [
      relationship("fallback"),
      relationship("snake", sections: [snake]),
      relationship("camel", sections: [camel]),
      relationship("typed", sections: [typed]),
    ]

    scene = described_class.from_graph({ children: children, edges: edges })
    sections = scene.edges.to_h { |edge| [edge.id, edge.sections.first] }

    expect(sections.fetch("fallback").start_point.x).to eq(100.0)
    expect(sections.fetch("snake").bend_points.first.y).to eq(30.0)
    expect(sections.fetch("camel").bend_points.first.y).to eq(35.0)
    expect(sections.fetch("typed")).to equal(typed)
  end

  it "emits the four cardinality marker combinations" do
    cardinalities = %w[one zero_or_one one_or_more zero_or_more]
    edges = cardinalities.map do |cardinality|
      relationship(cardinality).tap do |item|
        item[:metadata] = {
          cardinality_from: cardinality,
          cardinality_to: cardinality,
        }
      end
    end

    markers = described_class.from_graph({ children: children, edges: edges })
      .edges.to_h { |edge| [edge.id, edge.source_marker] }

    expect(markers.fetch("one").lines.length).to eq(1)
    expect(markers.fetch("zero_or_one"))
      .to have_attributes(circle_first: true)
    expect(markers.fetch("zero_or_one").circles.length).to eq(1)
    expect(markers.fetch("one_or_more").lines.length).to eq(4)
    expect(markers.fetch("zero_or_more").circles.length).to eq(1)
    expect(markers.fetch("zero_or_more").lines.length).to eq(3)
  end

  it "keeps explicit empty sections empty without labels or markers" do
    edge = relationship("empty", sections: [])
    scene_edge = described_class.from_graph({ children: children, edges: [edge] })
      .edges.first

    expect(scene_edge.sections).to be_empty
    expect(scene_edge.labels).to be_empty
    expect(scene_edge.source_marker.lines).to be_empty
    expect(scene_edge.source_marker.circles).to be_empty
    expect(scene_edge.target_marker.lines).to be_empty
    expect(scene_edge.target_marker.circles).to be_empty
  end

  it "ignores endpoint-position labels when choosing the relationship label" do
    edge = relationship("labels")
    edge[:labels] = [
      { text: "source", position: "source" },
      { text: "relationship" },
      { text: "target", position: "target" },
    ]

    label = described_class.from_graph({ children: children, edges: [edge] })
      .edges.first.labels.first

    expect(label.text).to eq("relationship")
    expect([label.x, label.y]).to eq([150.0, 25.0])
  end
end
