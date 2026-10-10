# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4Placement do
  let(:scene) do
    source = File.read("spec/mermaid/c4/007_example_c4_6.mmd")
    Sirena::Layout::C4.new.call(Sirena::Parser::C4.new.parse(source))
  end
  let(:outer) { scene.children.find { |node| node.id == "b0" } }

  def nodes_under(node)
    node.children.flat_map { |child| [child, *nodes_under(child)] }
  end

  def box
    { width: 40, height: 40, metadata: {} }
  end

  def graph_of(count, config = nil)
    {
      children: Array.new(count) { box },
      metadata: { layout_config: config },
    }
  end

  # The numbers below are read off the mmdc render of c4/007.
  it "places the outer boundary where mmdc does" do
    expect([outer.x, outer.y, outer.height]).to eq([150, 122, 2191])
  end

  it "puts the first box inside the outer boundary" do
    first = outer.children.find { |node| node.kind == "person" }
    expect([first.x, first.y]).to eq([200, 222])
  end

  it "writes absolute coordinates for a box in a nested boundary" do
    inner = nodes_under(outer).find { |node| node.id == "b2" }
    expect([inner.x, inner.y]).to eq([250, 1791])
  end

  it "grows the canvas 60 px for a title and shifts its origin" do
    expect([scene.height, scene.view_box.split.fetch(1)])
      .to eq([2483, "-70"])
  end

  it "puts the title 20 px from the top of the content" do
    expect(scene.title.y).to eq(20)
  end

  it "sizes the canvas 150 beyond the widest boundary" do
    expect(scene.width).to eq(outer.x + outer.width + 150)
  end

  it "keeps four boxes in one row by default" do
    graph = described_class.apply(graph_of(4))
    expect(graph[:children].map { |node| node[:y] }.uniq.length).to eq(1)
  end

  it "wraps the fifth box to a second row by default" do
    graph = described_class.apply(graph_of(5))
    expect(graph[:children].map { |node| node[:y] }.uniq.length).to eq(2)
  end

  it "honours a shapeInRow setting" do
    config = 'UpdateLayoutConfig($c4ShapeInRow="1")'
    graph = described_class.apply(graph_of(3, config))
    expect(graph[:children].map { |node| node[:y] }.uniq.length).to eq(3)
  end

  it "returns the canvas in the graph metadata" do
    graph = described_class.apply(graph_of(1))
    expect(graph.dig(:metadata, :canvas)).to include(:width, :height)
  end
end
