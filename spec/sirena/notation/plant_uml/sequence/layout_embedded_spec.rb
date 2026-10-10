# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include PlantUmlSequenceTitleHelpers

  let(:small) { laid_out(*nested_note("X -> Y")) }
  let(:doubled) { laid_out(*nested_note("scale 2", "X -> Y")) }

  it "keeps the embedded diagram as a picture in the note" do
    expect(small.notes.first.picture.scene.arrows.size).to eq(1)
  end

  it "records the scale of the picture" do
    expect(doubled.notes.first.picture.scale).to eq(2.0)
  end

  it "draws no note text beside the picture" do
    expect(small.notes.first.texts).to be_empty
  end

  it "makes the note larger for a larger scale" do
    expect(doubled.height).to be > small.height
  end

  it "keeps a tall note below the participant heads" do
    top = small.heads.first.y + small.heads.first.height

    expect(doubled.notes.first.path[/M \S+ (\S+)/, 1].to_f).to be >= top
  end

  it "lays out a note inside the embedded diagram too" do
    inner = laid_out(*nested_note("X -> Y", *nested_note("P -> Q")))
    picture = inner.notes.first.picture

    expect(picture.scene.notes.first.picture).not_to be_nil
  end
end
