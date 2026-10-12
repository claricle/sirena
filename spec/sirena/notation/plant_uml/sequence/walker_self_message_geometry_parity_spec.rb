# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Walker do
  let(:sequence) { Sirena::Notation::PlantUML::Sequence }

  def arrow_style(leftward)
    sequence::ArrowStyle.new(
      head: sequence::ArrowEnd.new(glyph: :filled), leftward: leftward,
    )
  end

  def self_message(leftward)
    sequence::Message.new(
      from: "A", to: "A", label: "call", style: arrow_style(leftward),
    )
  end

  def walker
    described_class.new(
      lifelines: { "A" => 50.0 }, measure: ->(text) { text.length * 7.0 },
      font_size: 14.0, start_y: 100.0
    )
  end

  def loop_height(leftward:)
    coordinates = walker.run([self_message(leftward)]).arrows.first.path
      .scan(/-?\d+(?:\.\d+)?/).map(&:to_f)

    coordinates[5] - coordinates[1]
  end

  it "matches PlantUML self-message loop height in both directions" do
    heights = [false, true].map { |leftward| loop_height(leftward:) }

    expect(heights).to eq([13.0, 13.0])
  end
end
