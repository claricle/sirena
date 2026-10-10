# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::SequenceRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  let(:participant_tops) do
    [
      [:"participant-top", "Alice", "Alice"],
      [:"participant-top", "Bob", "Bob"],
    ]
  end

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.label]
    end.sort_by { |kind, key, _label| [kind, key] }
  end

  def failure_identities(reference, sirena)
    figures = [reference, sirena].map { |svg| extract(svg, recognizer) }
    match = SpecSupport::LayoutParity::ElementMatcher.match(
      reference: figures.first, sirena: figures.last,
    )
    match[:failures].map { |failure| failure.values_at(:type, :group) }
  end

  it "maps a real pair to the same semantic participants" do
    reference, sirena = sequence_sides

    expect([recognized(reference), recognized(sirena)])
      .to eq([participant_tops, participant_tops])
  end

  it "keeps participant-set differences visible" do
    reference, = sequence_sides
    alice = Sirena.render("sequenceDiagram\n  Alice->>Alice: Hi\n")

    expect(failure_identities(reference, alice))
      .to eq([[:missing, [:"participant-top", nil, "Bob"]]])
  end
end
