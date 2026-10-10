# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::ErrorRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.label]
    end
  end

  def candidate_svg
    <<~SVG
      <svg viewBox="0 0 200 100">
        <rect x="10" y="10" width="180" height="80"/>
        <circle cx="40" cy="50" r="20"/>
        <rect x="38" y="40" width="4" height="12"/>
        <circle cx="40" cy="56" r="2"/>
        <text x="70" y="50">Error</text>
      </svg>
    SVG
  end

  def real_pair
    name = "002_rendering_errordiagram_spec_error_1"
    reference = reference_svg("error/#{name}.svg")
    sirena = Sirena.render(corpus_source("error/#{name}.mmd"))
    [recognized(reference), recognized(sirena)]
  end

  def matched_real_pair
    name = "002_rendering_errordiagram_spec_error_1"
    reference = extract(reference_svg("error/#{name}.svg"), recognizer)
    sirena = extract(
      Sirena.render(corpus_source("error/#{name}.mmd")), recognizer
    )
    SpecSupport::LayoutParity::ElementMatcher.match(
      reference: reference, sirena: sirena,
    )
  end

  def expected_pair
    [
      [[:error_icon, "error-icon", nil, nil],
       [:error_text, "message", nil, "Syntax error in text"],
       [:error_text, "version", nil, "mermaid version 11.12.0"]],
      [[:error_icon, "error-icon", nil, nil],
       [:error_text, "message", nil, "Error"]],
    ]
  end

  def match_summary
    result = matched_real_pair
    [result[:pairs].map { |pair| pair.map(&:key) }, result[:failures]]
  end

  it "unions only the candidate icon primitives" do
    figure = extract(candidate_svg, recognizer)

    expect(box_of(figure, "error-icon")).to eq([20.0, 30.0, 60.0, 70.0])
  end

  it "uses fixed icon and text roles for a real pair" do
    expect(real_pair).to eq(expected_pair)
  end

  it "matches shared fixed roles while retaining a missing version role" do
    expect(match_summary).to match(
      [[%w[error-icon error-icon], %w[message message]],
       [include(type: :missing, group: [:error_text, nil, "version"])]],
    )
  end
end
