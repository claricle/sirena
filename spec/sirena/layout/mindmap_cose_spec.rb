# frozen_string_literal: true

require "json"
require "spec_helper"
require "sirena/layout/mindmap_cose"

module MindmapCoseReferenceHelpers
  # Lays out a reference case with the box sizes read from its mmdc SVG, so
  # a difference in a centre is the layout's, not the text measurement's.
  def reference_layout(name)
    nodes = MindmapReference.nodes(name)
    sizes = nodes.map { |node| [node[:id], *node[:size]] }
    placed = described_class.call(sizes, MindmapReference.edges(name))
    [nodes, placed]
  end

  def offsets_from_first(centres)
    root = centres.first
    centres.map { |centre| [centre[0] - root[0], centre[1] - root[1]] }
  end

  # The placed centres of +nodes+ relative to the first, as one flat list.
  def layout_offsets(nodes, placed)
    offsets_from_first(nodes.map { |node| placed.fetch(node[:id]) }).flatten
  end

  # The mmdc centres of +nodes+ relative to the first, as one flat list.
  def reference_offsets(nodes)
    offsets_from_first(nodes.map { |node| node[:centre] }).flatten
  end

  def match_offsets(expected)
    match(expected.map { |value| be_within(0.01).of(value) })
  end

  def fixture_nodes(fixture)
    fixture["nodes"].map { |node| { id: node["id"], centre: node["centre"] } }
  end

  def fixture_placement(fixture)
    sizes = fixture["nodes"].map { |n| [n["id"], n["width"], n["height"]] }
    described_class.call(sizes, fixture["edges"])
  end
end

RSpec.describe Sirena::Layout::MindmapCose do
  include MindmapCoseReferenceHelpers

  {
    "016" => "a root with two children",
    "028" => "a root with two children of equal width",
    "030" => "a three-level chain",
    "017" => "a root with a nested branch",
    "009" => "ten nodes over three levels",
  }.each do |name, description|
    it "puts #{description} where mmdc does (#{name})" do
      nodes, placed = reference_layout(name)

      expect(layout_offsets(nodes, placed))
        .to match_offsets(reference_offsets(nodes))
    end
  end

  # Layouts mmdc 11.12.0 produced in Chrome 131 from the fixture's source,
  # with the box sizes mmdc measured. The symmetric trees turn a last-bit
  # difference in the seed's sin and cos into a visibly different layout.
  Dir[File.join(__dir__, "../../fixtures/mindmap_cose/*.json")].each do |path|
    name = File.basename(path, ".json")
    it "puts every node where mmdc does (#{name})" do
      fixture = JSON.parse(File.read(path))
      nodes = fixture_nodes(fixture)
      placed = fixture_placement(fixture)

      expect(layout_offsets(nodes, placed))
        .to match_offsets(reference_offsets(nodes))
    end
  end

  it "places the root's children left and right of it on its row (028)" do
    nodes, placed = reference_layout("028")
    root, first, second = nodes.map { |node| placed.fetch(node[:id]) }

    expect([first[1] - root[1], second[1] - root[1],
            first[0] > root[0], second[0] < root[0]])
      .to eq([0.0, 0.0, true, true])
  end

  it "keeps the left of the margin-padded layout at the origin" do
    sizes = [["a", 60, 34], ["b", 80, 34]]
    placed = described_class.call(sizes, [%w[a b]])
    left = placed.map { |id, centre| centre[0] - (sizes.assoc(id)[1] / 2.0) }

    expect(left.min).to be_within(1e-9).of(described_class::MARGIN)
  end

  it "returns no positions for no nodes" do
    expect(described_class.call([], [])).to eq({})
  end

  it "places a lone node at half its size inside the margin" do
    expect(described_class.call([["a", 60, 34]], [])["a"])
      .to eq([45.0, 32.0])
  end
end
