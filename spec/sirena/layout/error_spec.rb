# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/error"

RSpec.describe Sirena::Layout::Error do
  subject(:scene) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Error.new }

  it "keeps a missing message for the renderer's default" do
    expect(scene_geometry).to eq(
      [described_class::Scene, "error", nil, "Error", 500.0, 220.0],
    )
  end

  it "preserves explicit identity, title, and message" do
    populate_diagram
    expect(scene_geometry).to eq(
      [described_class::Scene, "failure", "Build failed",
       "Dependency missing", 500.0, 220.0],
    )
  end

  def scene_geometry
    [scene.class, scene.id, scene.title, scene.label.text,
     scene.width, scene.height]
  end

  def populate_diagram
    diagram.id = "failure"
    diagram.title = "Build failed"
    diagram.message = "Dependency missing"
  end
end
