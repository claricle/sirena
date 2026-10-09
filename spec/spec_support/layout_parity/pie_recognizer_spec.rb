# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::PieRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.identity]
    end
  end

  def real_pair(name)
    reference = reference_svg("pie/#{name}.svg")
    sirena = Sirena.render(corpus_source("pie/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  def value_sorted_expected
    reference = %w[Football Ice-Hockey Bandy]
    sirena = %w[Bandy Ice-Hockey Football]
    [reference, sirena].map do |labels|
      labels.map { |label| [:pie_sector, label, :label] }
    end
  end

  def sector(label)
    [:pie_sector, label, :label]
  end

  it "associates value-sorted reference sectors with legend labels" do
    expect(real_pair("002_rendering_pie_spec_pie_1"))
      .to eq(value_sorted_expected)
  end

  it "normalizes show-data suffixes to the underlying section label" do
    name = "014_parser_should_handle_simple_pie_with_showdata_13"
    expected = %w[ash bat].map { |label| [:pie_sector, label, :label] }

    expect(real_pair(name)).to eq([expected, expected])
  end

  it "keeps the candidate's zero-value sector visible as parity evidence" do
    name = "022_parser_should_handle_simple_pie_with_zero_slice_value_21"
    expect(real_pair(name)).to eq([[sector("rats")],
                                   [sector("dogs"), sector("rats")]])
  end
end
