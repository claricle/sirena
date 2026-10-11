# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::SvgFigureExtractor do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:svg) do
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">
        <g class="node" id="flowchart-stretch-0">
          <svg x="10" y="20" width="80" height="40"
               viewBox="5 10 20 20" preserveAspectRatio="none">
            <rect x="7" y="13" width="4" height="5"/>
          </svg>
        </g>
      </svg>
    SVG
  end

  it "independently scales both axes inside the nested viewport" do
    figure = extract(svg, SpecSupport::LayoutParity::FlowchartRecognizer.new)

    expect(box_of(figure, "stretch")).to eq([18.0, 26.0, 34.0, 36.0])
  end
end
