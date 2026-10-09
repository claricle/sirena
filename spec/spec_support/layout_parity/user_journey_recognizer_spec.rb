# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::UserJourneyRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key]
    end.sort
  end

  def real_pair
    name = "002_rendering_journey_spec_user_journey_1"
    reference = reference_svg("user_journey/#{name}.svg")
    sirena = Sirena.render(corpus_source("user_journey/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "uses the same section and task identities for a real pair" do
    reference_summary, sirena_summary = real_pair

    expect(sirena_summary).to eq(reference_summary)
  end
end
