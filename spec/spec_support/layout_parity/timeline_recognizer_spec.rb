# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::TimelineRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key]
    end.sort
  end

  def real_pair
    name = "001_rendering_timeline_spec_timeline_0"
    reference = reference_svg("timeline/#{name}.svg")
    sirena = Sirena.render(corpus_source("timeline/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "ignores axis annotations while matching periods and events" do
    reference_summary, sirena_summary = real_pair

    expect(sirena_summary).to eq(reference_summary)
  end
end
