# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::StateDiagram do
  subject(:renderer) { described_class.new }

  def unknown_shape_scene
    node = Sirena::Layout::StateDiagram::Node.new(
      id: "custom", x: 1, y: 2, width: 30, height: 40,
      shape_type: "custom"
    )
    Sirena::Layout::StateDiagram::Scene.new(
      id: "state_diagram", width: 50, height: 60,
      view_box: "0 0 50 60", children: [node], edges: []
    )
  end

  it "rejects even an otherwise renderable legacy graph" do
    graph = { id: "s", children: [{ id: "a" }], edges: [] }

    expect { renderer.render(graph) }.to raise_error(
      ArgumentError, "StateDiagram renderer requires a typed Scene"
    )
  end

  it "draws an unknown final shape as a normal state" do
    expect(renderer.render(unknown_shape_scene).to_xml)
      .to include('x="1.0" y="2.0" width="30.0" height="40.0"')
  end
end
