# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/info"

RSpec.describe Sirena::Layout::Info do
  subject(:scene) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Info.new }

  it "defaults the identifier and showInfo state" do
    expect(scene_geometry).to eq(
      [described_class::Scene, "info", nil, 500.0, 200.0,
       [50.0, 50.0, 400.0, 100.0, 8.0], "Info"],
    )
  end

  it "preserves an explicit identifier, title, and enabled showInfo state" do
    populate_diagram
    expect(scene_geometry).to eq(
      [described_class::Scene, "status", "System status", 500.0, 200.0,
       [50.0, 50.0, 400.0, 100.0, 8.0], "Info: showInfo enabled"],
    )
  end

  def scene_geometry
    scene_identity + [box_geometry, scene.label.text]
  end

  def scene_identity
    [scene.class, scene.id, scene.title, scene.width, scene.height]
  end

  def box_geometry
    [scene.box.x, scene.box.y, scene.box.width, scene.box.height,
     scene.box.corner_radius]
  end

  def populate_diagram
    diagram.id = "status"
    diagram.title = "System status"
    diagram.show_info = true
  end
end
