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

  def identity_summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent]
    end.sort_by { |item| item.map(&:to_s) }
  end

  def real_pair(name)
    reference = reference_svg("block/#{name}.svg")
    sirena = Sirena.render(corpus_source("block/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "matches anonymous compounds and their labeled leaves" do
    name = "block_spec-532fdf55"
    reference_summary, sirena_summary = real_pair(name)

    expect(sirena_summary).to eq(reference_summary)
  end

  it "matches semantic-id compounds and scopes their nested leaves" do
    name = "block-b7a88657"
    reference = reference_svg("block/#{name}.svg")
    sirena = Sirena.render(corpus_source("block/#{name}.mmd"))

    expect(identity_summaries(sirena)).to eq(identity_summaries(reference))
  end
end
