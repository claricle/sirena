# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::C4Recognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent]
    end.sort_by { |item| item.map(&:to_s) }
  end

  def real_pair
    name = "007_example_c4_6"
    reference = reference_svg("c4/#{name}.svg")
    sirena = Sirena.render(corpus_source("c4/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  def identities(summary)
    summary.map { |kind, key, _parent| [kind, key] }
  end

  def parent_map(summary)
    summary.to_h { |_kind, key, parent| [key, parent] }
  end

  it "matches boundary and element labels" do
    reference_summary, sirena_summary = real_pair

    expect(identities(sirena_summary)).to eq(identities(reference_summary))
  end

  it "matches the containment of the reference" do
    reference_summary, sirena_summary = real_pair
    parents = [parent_map(reference_summary), parent_map(sirena_summary)]

    expect(parents.map { |map| map.fetch("Banking Customer A") })
      .to eq(%w[BankBoundary0 BankBoundary0])
  end
end
