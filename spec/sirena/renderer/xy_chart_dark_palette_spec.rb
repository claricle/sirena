# frozen_string_literal: true

require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::XyChart do
  let(:palette) do
    %w[#3794ff #858585 #4ec9b0 #f48771 #dcdcaa #89d185 #9cdcfe
       #969696 #fbbf24 #d4d4d4]
  end
  let(:source) do
    series = Array.new(10) do |index|
      "  line [#{index + 1}, #{index + 2}, #{index + 3}]"
    end
    (["xychart-beta", "  x-axis [a, b, c]", "  y-axis 0 --> 20"] + series)
      .join("\n")
  end
  let(:document) do
    REXML::Document.new(Sirena.render(source, theme: :dark))
  end

  it "uses every dark series colour for lines and legends in order" do
    line_strokes = REXML::XPath.match(document, "//polyline/@stroke")
      .map(&:value)
    legend_fills = REXML::XPath.match(document, "//rect[@stroke='none']/@fill")
      .map(&:value)

    expect([line_strokes, legend_fills]).to eq([palette, palette])
  end
end
