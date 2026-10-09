# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::XyChartRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def keys(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key]
    end
  end

  def real_pair
    name = "001_example_xychart_0"
    reference = reference_svg("xychart/#{name}.svg")
    sirena = Sirena.render(corpus_source("xychart/#{name}.mmd"))
    [keys(reference), keys(sirena)]
  end

  it "matches every bar and line series by stable ordinal" do
    reference_keys, sirena_keys = real_pair

    expect(sirena_keys).to eq(reference_keys)
  end
end
