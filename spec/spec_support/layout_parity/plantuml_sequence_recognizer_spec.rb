# frozen_string_literal: true

require "spec_helper"

module PlantumlSequenceSvgs
  REFERENCE = <<~SVG
    <svg viewBox="0 0 200 200">
      <g class="participant participant-head" data-qualified-name="a">
        <rect x="5" y="5" width="40" height="20"/><text>Alice</text></g>
      <g class="participant participant-tail" data-qualified-name="a">
        <rect x="5" y="150" width="40" height="20"/><text>Alice</text></g>
      <g class="message" id="msg1">
        <line x1="25" y1="60" x2="90" y2="60"/><text>hi</text></g>
      <g class="message" id="msg2">
        <line x1="90" y1="80" x2="25" y2="80"/><text>back</text></g>
    </svg>
  SVG
  SIRENA = <<~SVG
    <svg viewBox="0 0 200 200">
      <g id="participant-a-150.0"><rect x="5" y="150" width="40" height="20"/>
        <text>Alice</text></g>
      <g id="participant-a-5.0"><rect x="5" y="5" width="40" height="20"/>
        <text>Alice</text></g>
      <g id="message-1"><path d="M 25 60 L 90 60"/><text>hi</text></g>
      <g id="message-7"><path d="M 90 80 L 25 80"/><text>back</text></g>
    </svg>
  SVG
  LEGACY_TEOZ = <<~SVG
    <svg viewBox="0 0 200 100">
      <g>
        <line x1="5" y1="20" x2="195" y2="20"
          style="stroke:#000;stroke-dasharray:2,2"/>
        <text x="10" y="32" font-size="11" font-weight="700">[fallback]</text>
        <polygon points="180,55 170,50 170,60"/>
        <line x1="20" y1="55" x2="180" y2="55"/>
        <text x="80" y="48" font-size="13">response</text>
      </g>
    </svg>
  SVG
  LEGACY_TEOZ_ACTOR = <<~SVG
    <svg viewBox="0 0 100 100">
      <g>
        <g><title>Mallory</title>
          <rect x="34" y="70" width="8" height="20" fill-opacity="0"/>
          <line x1="38" y1="70" x2="38" y2="90"
            style="stroke-dasharray:5,5"/>
        </g>
        <text x="10" y="84">Mallory</text>
        <ellipse cx="38" cy="18" rx="8" ry="8"/>
        <path d="M 38 26 L 38 53 M 25 34 L 51 34
          M 38 53 L 25 68 M 38 53 L 51 68"/>
      </g>
    </svg>
  SVG
end

RSpec.describe SpecSupport::LayoutParity::PlantumlSequenceRecognizer do
  subject(:recognizer) { described_class.new }

  include SpecSupport::LayoutParity::FigureHelpers

  def elements(svg)
    extract(svg, recognizer).elements
  end

  def keys(svg)
    elements(svg).map { |element| [element.kind, element.key] }
  end

  it "keys one participant per name from the head copy" do
    expect(keys(PlantumlSequenceSvgs::REFERENCE).first).to eq(
      [:participant, "a"],
    )
  end

  it "takes the topmost Sirena copy of a participant" do
    participant = elements(PlantumlSequenceSvgs::SIRENA).first
    expect(participant.bbox.min_y).to eq(5.0)
  end

  it "numbers messages by document order on both producers" do
    expect(keys(PlantumlSequenceSvgs::SIRENA)).to eq(
      keys(PlantumlSequenceSvgs::REFERENCE),
    )
  end

  it "labels a message with its text" do
    labels = elements(PlantumlSequenceSvgs::SIRENA).map(&:label)
    expect(labels).to eq(["Alice", "hi", "back"])
  end

  it "does not recognize a legacy Teoz fragment separator as a message" do
    labels = elements(PlantumlSequenceSvgs::LEGACY_TEOZ).map(&:label)
    expect(labels).to eq(["response"])
  end

  it "recognizes a legacy Teoz actor from its ellipse and path glyph" do
    actor = elements(PlantumlSequenceSvgs::LEGACY_TEOZ_ACTOR).first
    expect([actor.label, actor.bbox.width, actor.bbox.height])
      .to eq(["Mallory", 26.0, 58.0])
  end
end
