# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/error"

RSpec.describe Sirena::Layout::Error do
  subject(:scene) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Error.new }

  it "keeps a missing message for the renderer's default" do
    expect(scene_geometry).to eq(
      [described_class::Scene, "error", nil, "Error", 2412.0, 512.0],
    )
  end

  it "preserves explicit identity, title, and message" do
    populate_diagram
    expect(scene_geometry).to eq(
      [described_class::Scene, "failure", "Build failed",
       "Dependency missing", 2412.0, 512.0],
    )
  end

  it "lays out shared data IR identically to the private model" do
    populate_diagram
    ir = Sirena::Notation::Mermaid::IRAdapters::Error.call(diagram)
    ir_scene = described_class.new.call(ir)

    expect(scene_geometry(ir_scene)).to eq(scene_geometry)
  end

  def scene_geometry(value = scene)
    [value.class, value.id, value.title, value.label.text,
     value.width, value.height]
  end

  def populate_diagram
    diagram.id = "failure"
    diagram.title = "Build failed"
    diagram.message = "Dependency missing"
  end
end
