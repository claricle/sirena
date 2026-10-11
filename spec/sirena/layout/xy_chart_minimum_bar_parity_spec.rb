# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::XyChart do
  let(:source) do
    categories = %w[jan feb mar apr may jun jul aug sep oct nov dec].join(", ")
    values = [4000, 6000, 7500, 8200, 9500, 10_500,
              11_000, 10_200, 9200, 8500, 7000, 6000].join(", ")
    <<~MERMAID
      xychart-beta
          title "Sales Revenue"
          x-axis [#{categories}]
          y-axis "Revenue (in $)" 4000 --> 11000
          bar [#{values}]
    MERMAID
  end
  let(:diagram) { Sirena::Notation::Mermaid.parse(source).diagram }
  let(:bars) { described_class.new.call(diagram).series.first.bars }

  it "keeps a minimum-valued bar visible at the pinned baseline" do
    first = bars.first
    geometry = [first.x, first.y, first.width,
                first.height, first.y + first.height]

    expect(geometry).to eq([83.56875190734863, 459.0, 32.3, 8.0, 467.0])
  end

  it "terminates every bar at the common pinned baseline" do
    expect(bars.map { |bar| bar.y + bar.height }).to eq(Array.new(12, 467.0))
  end
end
