# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::RadarRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key]
    end
  end

  def real_pair
    name = "001_rendering_radar_spec_radar_0"
    reference = reference_svg("radar/#{name}.svg")
    sirena = Sirena.render(corpus_source("radar/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "matches axes, curves and the title on both producers" do
    reference_summary, sirena_summary = real_pair

    expect(sirena_summary).to match_array(reference_summary)
  end
end
