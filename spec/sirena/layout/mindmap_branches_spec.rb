# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/mindmap"
require "sirena/layout/mindmap"

RSpec.describe Sirena::Layout::Mindmap do
  def scene_for(source)
    diagram = Sirena::Parser::Mindmap.new.parse(source)
    described_class.new.call(diagram)
  end

  def reference_source(name)
    path = Dir[File.join(__dir__, "../../mermaid/mindmap/#{name}_*.mmd")].first
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

  describe "canvas and edges for a two-child mindmap (mmdc 028)" do
    let(:scene) { scene_for(reference_source("028")) }
    let(:reference_box) { MindmapReference.view_box("028") }

    it "frames the node boxes with 10 on every side" do
      boxes = scene.children
      extent = [boxes.map(&:x).min, boxes.map(&:y).min,
                boxes.map { |node| node.x + node.width }.max,
                boxes.map { |node| node.y + node.height }.max]

      expect([extent[0], extent[1], scene.width - extent[2],
              scene.height - extent[3]]).to eq([10.0, 10.0, 10.0, 10.0])
    end

    it "puts the first child right of the root and the second left, as mmdc does" do
      root, first, second = scene.children
      reference = MindmapReference.nodes("028").map { |node| node[:centre][0] }

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
      root, first = scene.children
      section = scene.edges.first.sections.first
      reference = MindmapReference.edge_paths("028").first
      nodes = MindmapReference.nodes("028")
      inset = Math.hypot(reference.first[0] - nodes.first[:centre][0],
                         reference.first[1] - nodes.first[:centre][1])

      expect([distance(section.start_point, centre_of(root)),
              distance(section.end_point, centre_of(first))])
        .to match([be_within(0.01).of(inset), be_within(0.01).of(inset)])
    end

    it "bends each edge through its midpoint as mmdc's curve does" do
      reference = path_fractions(MindmapReference.edge_paths("028").first)

      expect(path_fractions(scene_path_points(scene)))
        .to match(reference.map { |value| be_within(1e-3).of(value) })
    end
  end
end
