# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Pie do
  subject(:evidence) do
    [scene.legend.map { |entry| [entry.text, entry.color_index] },
     scene.slices.map do |slice|
       [slice.percentage, slice.angle, slice.color_index, slice.label.text]
     end]
  end

  let(:source) do
    <<~MERMAID
      pie showData
        "Positive" : 10
        "Positive" : 20
        "Other" : 10
    MERMAID
  end
  let(:diagram) { Sirena::Notation::Mermaid.parse(source).diagram }
  let(:scene) { described_class.new.call(diagram) }

  it "keeps the first value for a repeated Mermaid label" do
    expect(evidence).to eq(
      [[["Positive [10]", 0], ["Other [10]", 1]],
       [[50.0, 180.0, 0, "50%"], [50.0, 180.0, 1, "50%"]]],
    )
  end
end
