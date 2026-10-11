# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassCellPlacement do
  let(:fixture) { nil }

  let(:boxes) do
    path = File.expand_path("../../mermaid/class_diagram/#{fixture}.mmd",
                            __dir__)
    diagram = Sirena::Parser::ClassDiagram.new.parse(File.read(path))
    scene = Sirena::Layout::ClassDiagram.new.call(diagram)
    scene.children.to_h { |node| [node.id, [node.x, node.y]] }
  end

  context "with labelled relations from one class (mmdc: nodesep 50)" do
    let(:fixture) { "classdiagram_spec-36d00a43" }

    it "ranks the target classes side by side under the source" do
      placed = boxes.values_at("IdCard", "Bike", "Student")
      expect(placed.map { |pair| pair.map(&:round) })
        .to eq([[8, 196], [207, 196], [94, 8]])
    end
  end

  context "with classes that have no relations" do
    let(:fixture) { "classdiagram_elk_v3_spec-29977982" }

    it "lays them in one rank spaced 50 apart" do
      expect(boxes.values.map(&:last).uniq).to eq([8.0])
    end

    it "keeps declaration order along the rank" do
      xs = boxes.values.map(&:first)
      expect(xs).to eq(xs.sort)
    end
  end
end
