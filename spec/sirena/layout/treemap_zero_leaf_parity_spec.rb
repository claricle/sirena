# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Treemap do
  subject(:evidence) do
    children.map do |cell|
      box = cell.box
      [cell.label.text, cell.value_label.text,
       [box.x, box.y, box.width, box.height]]
    end
  end

  let(:source) do
    <<~MERMAID
      treemap-beta
        "Root"
          "Zero": 0
          "One": 1
    MERMAID
  end
  let(:diagram) { Sirena::Notation::Mermaid.parse(source).diagram }
  let(:children) { described_class.new.call(diagram).cells.first.children }

  it "retains a zero-weight leaf at Mermaid's collapsed trailing bounds" do
    expect(evidence).to eq(
      [["One", "1", [20.0, 70.0, 960.0, 310.0]],
       ["Zero", "0", [985.0, 70.0, 0.0, 310.0]]],
    )
  end
end
