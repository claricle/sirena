# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/info"

RSpec.describe Sirena::Layout::Info do
  subject(:scene) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Info.new }

  it "defaults the identifier and showInfo state" do
    expect(scene_geometry).to eq(
      [described_class::Scene, "info", nil, 400.0, 100.0, "v11.12.0"],
    )
  end

  it "preserves an explicit identifier, title, and enabled showInfo state" do
    populate_diagram
    expect(scene_geometry).to eq(
      [described_class::Scene, "status", "System status", 400.0, 100.0,
       "v11.12.0"],
    )
  end

  it "lays out shared data IR identically to the private model" do
    populate_diagram
    ir = Sirena::Notation::Mermaid::IRAdapters::Info.call(diagram)
    ir_scene = described_class.new.call(ir)

    expect(scene_geometry(ir_scene)).to eq(scene_geometry)
  end

  def scene_geometry(value = scene)
    scene_identity(value) + [value.label.text]
  end

  def scene_identity(value)
    [value.class, value.id, value.title, value.width, value.height]
  end

  def populate_diagram
    diagram.id = "status"
    diagram.title = "System status"
    diagram.show_info = true
  end
end
