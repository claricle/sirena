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
      id: id, sources: ["A"], targets: ["B"], labels: [{ text: id }],
      metadata: {
        cardinality_from: "one",
        cardinality_to: "zero_or_more",
      }
    }.merge(extra)
  end

  describe "section coordinate formats" do
    let(:typed) do
      described_class::Section.new(
        start_point: described_class::Point.new(x: 100, y: 15),
        end_point: described_class::Point.new(x: 200, y: 15),
      )
    end
    let(:snake) do
      {
        start_point: { x: 100, y: 20 },
        end_point: { x: 200, y: 20 },
        bend_points: [{ x: 150, y: 30 }],
      }
    end
    let(:camel) do
      {
        "startPoint" => { x: 100, y: 25 },
        "endPoint" => { x: 200, y: 25 },
        "bendPoints" => [{ x: 150, y: 35 }],
      }
    end
    let(:sections) do
      edges = [
        relationship("fallback"),
        relationship("snake", sections: [snake]),
        relationship("camel", sections: [camel]),
        relationship("typed", sections: [typed]),
      ]
      described_class.from_graph({ children: children, edges: edges })
        .edges.to_h { |edge| [edge.id, edge.sections.first] }
    end

    it "builds fallback sections" do
      expect(sections.fetch("fallback").start_point.x).to eq(100.0)
    end

    it "accepts snake-case sections" do
      expect(sections.fetch("snake").bend_points.first.y).to eq(30.0)
    end

    it "accepts camel-case sections" do
      expect(sections.fetch("camel").bend_points.first.y).to eq(35.0)
    end

    it "preserves typed sections" do
      expect(sections.fetch("typed")).to equal(typed)
    end
  end

  describe "cardinality markers" do
    let(:cardinalities) do
      %w[one zero_or_one one_or_more zero_or_more]
    end
    let(:edges) do
      cardinalities.map do |cardinality|
        relationship(cardinality).tap do |item|
          item[:metadata] = {
            cardinality_from: cardinality,
            cardinality_to: cardinality,
          }
        end
      end
    end
    let(:markers) do
      described_class.from_graph({ children: children, edges: edges })
        .edges.to_h { |edge| [edge.id, edge.source_marker] }
    end

    it "builds one markers" do
      expect(markers.fetch("one").lines.length).to eq(1)
    end

    it "orders zero-or-one circles first" do
      expectation = expect(markers.fetch("zero_or_one"))
      expectation.to have_attributes(circle_first: true)
    end

    it "builds zero-or-one circles" do
      expect(markers.fetch("zero_or_one").circles.length).to eq(1)
    end

    it "builds one-or-more lines" do
      expect(markers.fetch("one_or_more").lines.length).to eq(4)
    end

    it "builds zero-or-more circles" do
      expect(markers.fetch("zero_or_more").circles.length).to eq(1)
    end

    it "builds zero-or-more lines" do
      expect(markers.fetch("zero_or_more").lines.length).to eq(3)
    end
  end

  describe "explicit empty sections" do
    let(:edge) { relationship("empty", sections: []) }
    let(:scene_edge) do
      described_class.from_graph({ children: children, edges: [edge] })
        .edges.first
    end

    it "keeps sections empty" do
      expect(scene_edge.sections).to be_empty
    end

    it "keeps labels empty" do
      expect(scene_edge.labels).to be_empty
    end

    it "keeps source marker lines empty" do
      expect(scene_edge.source_marker.lines).to be_empty
    end

    it "keeps source marker circles empty" do
      expect(scene_edge.source_marker.circles).to be_empty
    end

    it "keeps target marker lines empty" do
      expect(scene_edge.target_marker.lines).to be_empty
    end

    it "keeps target marker circles empty" do
      expect(scene_edge.target_marker.circles).to be_empty
    end
  end

  describe "relationship labels" do
    let(:edge) do
      relationship("labels").tap do |item|
        item[:labels] = [
          { text: "source", position: "source" },
          { text: "relationship" },
          { text: "target", position: "target" },
        ]
      end
    end
    let(:label) do
      described_class.from_graph({ children: children, edges: [edge] })
        .edges.first.labels.first
    end

    it "ignores endpoint-position labels" do
      expect(label.text).to eq("relationship")
    end

    it "centers the relationship label" do
      expect([label.x, label.y]).to eq([150.0, 25.0])
    end
  end
end
