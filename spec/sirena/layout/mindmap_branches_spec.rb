# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/mindmap"
require "sirena/layout/mindmap"

RSpec.describe Sirena::Layout::Mindmap do
  def scene_for(source)
    diagram = Sirena::Parser::Mindmap.new.parse(source)
    described_class.new.call(diagram)
  end

  it "returns a finite empty scene when no root exists" do
    scene = described_class.new.call(Sirena::Diagram::Mindmap.new)

    expect(scene).to have_attributes(
      width: 80.0, height: 80.0, children: [], edges: [],
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
end
