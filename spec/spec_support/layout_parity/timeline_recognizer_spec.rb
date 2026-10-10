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

  def pair_for(name)
    reference = reference_svg("timeline/#{name}.svg")
    sirena = Sirena.render(corpus_source("timeline/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "keeps a section that has no tasks" do
    reference_summary, sirena_summary =
      pair_for("008_parser_should_handle_a_simple_section_definition_abc-123_7")

    expect(sirena_summary).to eq(reference_summary)
  end

  it "reads the section label of a task-less timeline" do
    summary, = pair_for(
      "008_parser_should_handle_a_simple_section_definition_abc-123_7",
    )

    expect(summary).to include([:timeline_section, "abc-123"])
  end

  it "measures the axis of an empty timeline" do
    summary, = pair_for("006_rendering_timeline_spec_timeline_5")

    expect(summary).to eq([[:timeline_axis, "axis"]])
  end

  it "ignores axis annotations while matching periods and events" do
    reference_summary, sirena_summary = real_pair

    expect(sirena_summary).to eq(reference_summary)
  end
end
