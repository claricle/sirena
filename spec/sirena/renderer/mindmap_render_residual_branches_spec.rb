# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Mindmap, "#render" do
  let(:scene) do
    diagram = Sirena::Parser::Mindmap.new.parse("mindmap\n  root((Root))\n")
    Sirena::Layout::Mindmap.new.call(diagram)
  end
  let(:node) { scene.children.first }
  let(:xml) { described_class.new.render(scene).to_xml }

  it "writes the node label" do
    expect(xml).to include(">Root<")
  end

  it "writes no text for a node without labels" do
    node.labels = []

    expect(xml).not_to include("<text")
  end

  it "writes no text for a label without text" do
    node.labels.first.text = nil

    expect(xml).not_to include("<text")
  end
end
