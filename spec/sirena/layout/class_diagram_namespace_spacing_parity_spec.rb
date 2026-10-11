# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  let(:boxes) do
    path = File.expand_path(
      "../../mermaid/class_diagram/classdiagram_spec-2fe166c9.mmd", __dir__
    )
    diagram = Sirena::Parser::ClassDiagram.new.parse(File.read(path))
    described_class.new.call(diagram).children.to_h { |node| [node.id, node] }
  end

  it "spaces sibling classes in a namespace 50 apart, as mmdc's dagre does" do
    a1, a2 = boxes.values_at("A1", "A2")
    expect((a2.x - (a1.x + a1.width)).round(3)).to eq(50.0)
  end

  it "keeps the sibling classes in one rank" do
    expect(boxes.values_at("A1", "A2").map(&:y).uniq.size).to eq(1)
  end
end
