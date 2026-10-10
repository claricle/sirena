# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Block, :aggregate_failures do
  subject(:renderer) { described_class.new }

  let(:source) { File.read("examples/block/01-basic-blocks.mmd") }
  let(:svg) { renderer.render(scene) }
  let(:xml) { svg.to_xml }
  let(:expected_path) do
    "M #{section.start_point.x} #{section.start_point.y} " \
      "L #{section.end_point.x} #{section.end_point.y}"
  end

  def scene
    diagram = Sirena::Parser::Block.new.parse(source)
    @scene ||= Sirena::Layout::Block.new.call(diagram)
  end

  def section
    scene.edges.first.sections.first
  end

  it "renders typed final geometry with the Scene canvas" do
    expect(svg).to be_a(Sirena::Svg::Document)
    expect(scene).to be_a(Sirena::Layout::Block::Scene)
    expect(scene.children).to all(be_a(Sirena::Layout::Block::Node))
    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end

  it "renders blocks and labels" do
    expect(xml).to include('id="block-Frontend"', "Frontend App")
  end

  it "renders connections from the typed section" do
    expect(xml).to include('id="connection-Frontend-Backend"',
                           %(d="#{expected_path}"))
  end

  it "renders arrowheads without unresolved markers" do
    expect([xml.include?("<polygon"), xml.include?("marker-end")])
      .to eq([true, false])
  end

  it "stores final label and edge coordinates in the Scene" do
    node = scene.children.first
    expect([node.labels.first.x, node.labels.first.y, section.start_point.x])
      .to match([node.x + (node.width / 2), node.y + (node.height / 2),
                 a_kind_of(Numeric)])
  end
end
