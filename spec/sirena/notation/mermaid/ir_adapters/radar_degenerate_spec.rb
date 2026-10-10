# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/radar"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Radar do
  let(:diagram) do
    Sirena::Diagram::Radar.new.tap do |radar|
      radar.axes = [Sirena::Diagram::RadarAxis.new("a", "A"),
                    Sirena::Diagram::RadarAxis.new("a", "B")]
      radar.curves = []
      radar.options = {}
    end
  end

  it "gives two axes with the same id distinct dimension ids" do
    ids = described_class.call(diagram).dimensions.map(&:id)

    expect(ids).to eq(%w[a a_2])
  end
end
