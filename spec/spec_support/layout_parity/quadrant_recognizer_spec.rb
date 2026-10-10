# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::QuadrantRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent]
    end.sort_by { |item| item.map(&:to_s) }
  end

  def real_pair(name = "001_example_quadrant-chart_0")
    reference = reference_svg("quadrant/#{name}.svg")
    sirena = Sirena.render(corpus_source("quadrant/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "matches region and point identities with containment parents" do
    reference_summary, sirena_summary = real_pair

    expect(sirena_summary).to eq(reference_summary)
  end

  it "assigns a boundary-straddling point by its center" do
    pair = real_pair(
      "003_parser_should_throw_error_if_quadrantchart_text_is_not_there_2",
    )
    ibm_points = pair.map do |summary|
      summary.find { |kind, key, _parent| kind == :quadrant_point && key == "IBM" }
    end

    expect(ibm_points).to eq(
      Array.new(2, [:quadrant_point, "IBM", "Visionaries"]),
    )
  end
end
