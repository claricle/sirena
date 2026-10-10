# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/class_diagram"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::ClassDiagram do
  let(:entities) do
    %w[twin twin twin].map do |id|
      Sirena::Diagram::ClassEntity.new(id: id)
    end
  end
  let(:diagram) do
    Sirena::Diagram::ClassDiagram.new(id: "", entities: entities)
  end
  let(:ir) { described_class.call(diagram) }

  it "falls back to a generic id for an empty diagram id" do
    expect(ir.id).to eq("item")
  end

  it "numbers an entity that arrives without an id" do
    blank = Sirena::Diagram::ClassEntity.new(id: "")
    graph = described_class.call(
      Sirena::Diagram::ClassDiagram.new(entities: [blank]),
    )

    expect(graph.nodes.first.id).to eq("class_0")
  end

  it "skips every suffix that is already taken" do
    ids = ir.nodes.map(&:id) & %w[twin twin_2 twin_3]

    expect(ids).to eq(%w[twin twin_2 twin_3])
  end
end
