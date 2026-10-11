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
end
