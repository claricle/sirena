# frozen_string_literal: true

# mmdc (dagre) gives an edge label its own rank, so a labelled link pushes
# its two nodes apart by the label's line box on top of the 50 between ranks:
# `graph TD;A--x|textNoSpace|B;` sits 74 apart at 16px, which is 50 + 24.
RSpec.describe Sirena::Layout::Flowchart::LayerSpacing do
  let(:builder) { FlowchartSceneBuilder }
  let(:label_box) { scene.edges.first.labels.first }

  context "with no label on the link" do
    let(:scene) { builder.scene("TD", [%w[A B]]) }

    it "leaves 50 between ranks" do
      expect(builder.gap(scene, "A", "B", :y)).to be_within(0.01).of(50)
    end
  end

  context "with a label on a TD link" do
    let(:scene) { builder.scene("TD", [["A", "B", "textNoSpace"]]) }

    it "adds the label's 1.5 line height below" do
      expect(builder.gap(scene, "A", "B", :y))
        .to be_within(0.01).of(50 + (label_box.height * 1.5))
    end
  end

  context "with a label on an LR link" do
    let(:scene) { builder.scene("LR", [["A", "B", "textNoSpace"]]) }

    it "adds the label's width beside" do
      expect(builder.gap(scene, "A", "B", :x))
        .to be_within(0.01).of(50 + label_box.width)
    end
  end

  # An edge over a layer puts its label in the gap after its first layer.
  context "with a link over a layer" do
    let(:scene) do
      builder.scene("TD", [["A", "B"], ["B", "C"], ["A", "C", "long"]])
    end

    it "puts the room of a two-rank link in the first gap" do
      expect(builder.gap(scene, "A", "B", :y)).to be > 60
    end

    it "leaves the second gap at 50" do
      expect(builder.gap(scene, "B", "C", :y)).to be_within(0.01).of(50)
    end
  end
end
