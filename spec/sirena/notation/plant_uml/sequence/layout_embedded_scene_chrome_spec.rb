# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include PlantUmlSequenceTitleHelpers

  let(:scene) do
    inner = nested_note("scale 0.5", "P -> Q")
    laid_out(*nested_note("scale 2", "X -> Y", *inner))
  end

  def note_width(note)
    xs = note.path.scan(/-?\d+\.?\d*/).map(&:to_f).each_slice(2).map(&:first)
    xs.max - xs.min
  end

  it "removes standalone canvas chrome from recursively embedded scenes" do
    outer = scene.notes.first
    picture = outer.picture
    expected = ((picture.scene.width - 30) * picture.scale) + 16

    expect(note_width(outer)).to be_within(0.01).of(expected)
  end
end
