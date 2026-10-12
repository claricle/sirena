# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include PlantUmlSequenceTitleHelpers

  it "centres an attached picture note around its message row" do
    scene = laid_out(*nested_note("scale 2", "X -> Y"))
    note_ys = scene.notes.first.path.scan(/-?\d+\.?\d*/).map(&:to_f)
      .each_slice(2).map(&:last)
    note_midpoint = (note_ys.min + note_ys.max) / 2

    expect(first_arrow_y(scene)).to be_within(0.01).of(note_midpoint - 10)
  end
end
