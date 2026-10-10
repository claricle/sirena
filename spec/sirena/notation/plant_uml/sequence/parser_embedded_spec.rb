# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Parser do
  include PlantUmlSequenceTitleHelpers

  let(:note_class) { Sirena::Notation::PlantUML::Sequence::Note }
  let(:note) { parsed_diagram(*nested_note("X -> Y")).items.last }

  it "keeps a block as the whole body of one note" do
    expect(note.embedded.body).to eq("X -> Y")
  end

  it "does not close the note at the end note of the block" do
    lines = nested_note("X -> Y", "note right", "hi", "end note")

    notes = parsed_diagram(*lines).items.grep(note_class)

    expect(notes.size).to eq(1)
  end

  it "refuses a block beside other note text" do
    lines = ["A -> B", "note right", "text", "{{", "X -> Y", "}}", "end note"]

    expect(refusal_for(*lines)).to have_attributes(
      construct: "embedded diagram beside other note text",
    )
  end

  it "refuses what the block itself cannot draw" do
    expect(refusal_for(*nested_note("X -> Y", "title **T**")).construct)
      .to eq("title in an embedded diagram")
  end
end
