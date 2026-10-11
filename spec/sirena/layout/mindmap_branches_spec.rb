# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/mindmap"
require "sirena/layout/mindmap"

module MindmapBranchesHelpers
  def scene_for(source)
    diagram = Sirena::Parser::Mindmap.new.parse(source)
    described_class.new.call(diagram)
  end

  def reference_source(name)
    path = File.join(__dir__, "../../mermaid/mindmap/#{name}.mmd")
    File.read(path)
  end

  def distance(point, centre)
    Math.hypot(point.x - centre[0], point.y - centre[1])
  end

  def centre_of(node)
    [node.center_x, node.y + (node.height / 2)]
  end

  # Where a coordinate lies between the first and last x of a path.
  def path_fractions(points)
    start_x = points.first[0]
    span = points.last[0] - start_x
    points.map { |x, _| (x - start_x) / span }
  end

  def scene_path_points(scene)
    scene.edges.first.path.scan(/-?\d+\.?\d*/).map(&:to_f).each_slice(2).to_a
  end

  # Gaps between the node boxes and the left, top, right and bottom of the
  # canvas.
  def canvas_margins(scene)
    left, right = axis_extent(scene.children, :x, :width)
    top, bottom = axis_extent(scene.children, :y, :height)
    [left, top, scene.width - right, scene.height - bottom]
  end

  def axis_extent(boxes, origin, size)
    [boxes.map(&origin).min,
     boxes.map { |box| box.public_send(origin) + box.public_send(size) }.max]
  end

  # Distance from each end of the first edge to the centre of its node.
  def edge_end_distances(scene)
    root, first = scene.children
    section = scene.edges.first.sections.first
    [distance(section.start_point, centre_of(root)),
     distance(section.end_point, centre_of(first))]
  end

  # How far mmdc starts its first edge from the first node's centre.
  def reference_inset(name)
    start = MindmapReference.edge_paths(name).first.first
    centre = MindmapReference.nodes(name).first[:centre]
    Math.hypot(start[0] - centre[0], start[1] - centre[1])
  end
end

RSpec.describe Sirena::Layout::Mindmap do
  include MindmapBranchesHelpers

  it "returns a finite empty scene when no root exists" do
    scene = described_class.new.call(Sirena::Diagram::Mindmap.new)

    expect(scene).to have_attributes(
      width: 20.0, height: 20.0, children: [], edges: [],
    )
  end

  it "recursively assigns levels through a three-generation tree" do
    scene = scene_for("mindmap\n  root\n    child\n      grandchild\n")
    evidence = scene.children.map do |node|
      [node.labels.first.text, node.level]
    end

    expect(evidence).to eq([["root", 0], ["child", 1], ["grandchild", 2]])
  end

  it "centres a circle label by its radius" do
    root = scene_for("mindmap\n  root((Circle))\n").children.first
    label = root.labels.first

    expect([root.shape, label.y]).to eq(["circle", root.y + root.radius + 5])
  end

  it "sizes a node by mmdc's rule instead of a 100px minimum" do
    root = scene_for("mindmap\n  a\n").children.first

    expect(root.width).to be < 100
  end

  it "joins wrapped lines into the label with newlines" do
    source = "mindmap\n  a[one<br/>two]\n"

    expect(scene_for(source).children.first.labels.first.text)
      .to eq("one\ntwo")
  end

  describe "canvas and edges for a two-child mindmap (mmdc mmp_2 hierarchical)" do
    let(:scene) { scene_for(reference_source("mmp_2_should_handle_a_hierarchical_mindmap_defin-ad3719b5")) }
    let(:reference_box) { MindmapReference.view_box("mmp_2_should_handle_a_hierarchical_mindmap_defin-ad3719b5") }

    it "frames the node boxes with 10 on every side" do
      expect(canvas_margins(scene)).to eq([10.0, 10.0, 10.0, 10.0])
    end

    it "places the first child right and the second left, as mmdc does" do
      root, first, second = scene.children
      reference = MindmapReference.nodes("mmp_2_should_handle_a_hierarchical_mindmap_defin-ad3719b5").map { |node| node[:centre][0] }

      expect([first.center_x > root.center_x, second.center_x < root.center_x])
        .to eq([reference[1] > reference[0], reference[2] < reference[0]])
    end

    it "is as tall as the mmdc viewBox" do
      expect(scene.height).to eq(reference_box[3])
    end

    it "is as wide as the mmdc viewBox up to the text-width error" do
      expect(scene.width).to be_within(7).of(reference_box[2])
    end

    it "starts and ends each edge 15 from the node centres" do
      inset = be_within(0.01).of(reference_inset("mmp_2_should_handle_a_hierarchical_mindmap_defin-ad3719b5"))

      expect(edge_end_distances(scene)).to match([inset, inset])
    end

    it "bends each edge through its midpoint as mmdc's curve does" do
      reference = path_fractions(MindmapReference.edge_paths("mmp_2_should_handle_a_hierarchical_mindmap_defin-ad3719b5").first)

      expect(path_fractions(scene_path_points(scene)))
        .to match(reference.map { |value| be_within(1e-3).of(value) })
    end
  end
end
