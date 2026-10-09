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

  let(:participant_bottoms) do
    [
      [:"participant-bottom", "Alice", "Alice"],
      [:"participant-bottom", "Bob", "Bob"],
    ]
  end

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.label]
    end.sort_by { |kind, key, _label| [kind, key] }
  end

  it "maps a real pair to its producer-specific participant copies" do
    reference, sirena = sequence_sides

    expect([recognized(reference), recognized(sirena)])
      .to eq([participant_bottoms + participant_tops, participant_tops])
  end
end
