# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::TreemapRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent]
    end.sort_by { |item| [item.first.to_s, item[1]] }
  end

  def real_pair
    name = "001_rendering_treemap_spec_treemap_0"
    reference = reference_svg("treemap/#{name}.svg")
    sirena = Sirena.render(corpus_source("treemap/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "uses the same branch, leaf, and parent identities for a real pair" do
    reference_summary, sirena_summary = real_pair

    expect(sirena_summary).to eq(reference_summary)
  end
end
