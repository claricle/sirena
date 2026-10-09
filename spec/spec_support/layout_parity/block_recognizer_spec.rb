# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::BlockRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.label, element.parent]
    end.sort_by { |item| item.map(&:to_s) }
  end

  def real_pair
    name = "001_rendering_block_spec_block_0"
    reference = reference_svg("block/#{name}.svg")
    sirena = Sirena.render(corpus_source("block/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "matches anonymous compounds and their labeled leaves" do
    reference_summary, sirena_summary = real_pair

    expect(sirena_summary).to eq(reference_summary)
  end
end
