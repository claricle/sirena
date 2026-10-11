# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::SvgFigureExtractor do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:svg) do
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <g class="node" id="flowchart-label-0" transform="translate(3 4)">
          <text x="12" y="34">Label</text>
        </g>
      </svg>
    SVG
  end

  it "positions bare text without requiring a child tspan" do
    figure = extract(svg, SpecSupport::LayoutParity::FlowchartRecognizer.new)

    expect(box_of(figure, "label")).to eq([15.0, 38.0, 15.0, 38.0])
  end
end
