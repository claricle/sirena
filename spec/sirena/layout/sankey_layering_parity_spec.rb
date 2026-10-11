# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sankey do
  let(:source) do
    <<~MERMAID
      sankey-beta
        A,D,1
        A,B,1
        B,C,1
        C,D,1
    MERMAID
  end
  let(:diagram) { Sirena::Notation::Mermaid.parse(source).diagram }
  let(:scene) { described_class.new.call(diagram) }

  it "places a converging node after its longest predecessor chain" do
    layers = scene.nodes.to_h { |node| [node.id, node.layer] }

    expect(layers).to eq("A" => 0, "B" => 1, "C" => 2, "D" => 3)
  end

  it "keeps every non-self flow moving left to right" do
    forward_flows = scene.flows.reject(&:self_loop).map do |flow|
      flow.source_x < flow.target_x
    end

    expect(forward_flows).to all(be(true))
  end
end
