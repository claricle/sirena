# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Metrics do
  def node(kind, text)
    Sirena::Notation::PlantUML::NodeGraph::Node.new(id: text, kind: kind)
  end

  it "makes a short use case an ellipse hugging its text",
     :aggregate_failures do
    width, height = described_class.size(node(:usecase, "Start"))

    expect(width).to be_between(40, 60)
    expect(height).to be_within(0.001).of(29.318)
  end

  it "makes an actor as wide as its label, its figure above it",
     :aggregate_failures do
    width, height = described_class.size(node(:actor, "Main Admin"))

    expect(width).to be > 26
    expect(height).to eq(59.5 + described_class::LINE_HEIGHT)
  end

  it "keeps an actor at least as wide as its figure" do
    expect(described_class.size(node(:actor, "A")).first).to eq(26.0)
  end
end
