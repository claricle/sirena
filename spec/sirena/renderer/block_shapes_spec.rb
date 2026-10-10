# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Block do
  subject(:renderer) { described_class.new }

  def node(id, shape: "rect", direction: nil, label: id, **attributes)
    labels = if label
               [Sirena::Layout::Block::Label.new(text: label, x: 50, y: 30)]
             else
               []
             end
    Sirena::Layout::Block::Node.new(
      id: id, x: 0, y: 0, width: 100, height: 60, labels: labels,
      shape: shape, direction: direction, **attributes
    )
  end

  def scene(children: [], edges: [])
    Sirena::Layout::Block::Scene.new(
      width: 800, height: 600, view_box: "0 0 800 600",
      children: children, edges: edges
    )
  end

  def arrow_xml
    nodes = %w[up down left right sideways].map do |direction|
      node(direction, shape: "arrow", direction: direction, label: nil)
    end
    renderer.render(scene(children: nodes)).to_xml
  end

  def compound_xml
    child = node("kid")
    parent = node("group", compound: true, children: [child])
    renderer.render(scene(children: [parent])).to_xml
  end

  def connections_xml
    edge = typed_edge("e", "arrow", [1, 2], [3, 4])
    line = typed_edge("line", "line", [5, 6], [7, 8])
    renderer.render(scene(edges: [edge, line])).to_xml
  end

  def typed_edge(id, type, start_coords, end_coords)
    point = Sirena::Layout::Block::Point
    section = Sirena::Layout::Block::Section.new(
      start_point: point.new(x: start_coords[0], y: start_coords[1]),
      end_point: point.new(x: end_coords[0], y: end_coords[1]),
    )
    Sirena::Layout::Block::Edge.new(
      id: id, source: "a", target: "b", connection_type: type,
      sections: [section]
    )
  end

  let(:empty_svg) { renderer.render(scene) }

  it "renders an explicit empty typed Scene" do
    expect(empty_svg).to be_a(Sirena::Svg::Document)
  end

  it "uses the declared empty canvas" do
    expect([empty_svg.width, empty_svg.height, empty_svg.view_box])
      .to eq([800, 600, "0 0 800 600"])
  end

  it "draws up and down arrows" do
    expect(arrow_xml).to include('points="50.0,0.0 100.0,60.0 0.0,60.0"',
                                 'points="0.0,0.0 100.0,0.0 50.0,60.0"')
  end

  it "draws a left arrow" do
    expect(arrow_xml).to include('points="0.0,30.0 100.0,0.0 100.0,60.0"')
  end

  it "uses right for the arrow fallback" do
    expect(arrow_xml.scan('points="0.0,0.0 100.0,30.0 0.0,60.0"').size)
      .to eq(2)
  end

  it "omits labels when typed labels are empty" do
    expect(arrow_xml).not_to include("<text")
  end

  it "uses the smaller side for a circle radius" do
    circle = node("c", shape: "circle", width: 80, height: 40)
    xml = renderer.render(scene(children: [circle])).to_xml
    expect(xml).to match(/<circle[^>]*cx="40.0"[^>]*cy="20.0"[^>]*r="20.0"/)
  end

  it "renders a compound border" do
    expect(compound_xml).to include('stroke-dasharray="5,5"')
  end

  it "renders a compound child exactly once with its label" do
    evidence = [compound_xml.scan('id="block-kid"').size,
                compound_xml.include?(">kid<")]
    expect(evidence)
      .to eq([1, true])
  end

  it "draws each straight typed section" do
    expect(connections_xml).to include('d="M 1.0 2.0 L 3.0 4.0"',
                                       'd="M 5.0 6.0 L 7.0 8.0"')
  end

  it "draws an arrowhead only for the arrow edge" do
    expect(connections_xml.scan("<polygon").size).to eq(1)
  end
end
