# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::InfoRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.label]
    end
  end

  def real_pair
    name = "info_spec-e8bdfd49"
    reference = reference_svg("info/#{name}.svg")
    sirena = Sirena.render(corpus_source("info/#{name}.mmd"))
    [recognized(reference), recognized(sirena)]
  end

  def matched_real_pair
    name = "info_spec-e8bdfd49"
    reference = extract(reference_svg("info/#{name}.svg"), recognizer)
    sirena = extract(
      Sirena.render(corpus_source("info/#{name}.mmd")), recognizer
    )
    SpecSupport::LayoutParity::ElementMatcher.match(
      reference: reference, sirena: sirena,
    )
  end

  def match_summary
    result = matched_real_pair
    [result[:failures], result[:pairs].map { |pair| pair.map(&:key) }]
  end

  def expected_pair
    [[[:info_text, "info-text", nil, "v11.12.0"]],
     [[:info_text, "info-text", nil, "v11.12.0"]]]
  end

  it "gives both producers' version text the one fixed role" do
    expect(real_pair).to eq(expected_pair)
  end

  it "matches the fixed role instead of the producer-specific wording" do
    expect(match_summary).to eq([[], [["info-text", "info-text"]]])
  end
end
