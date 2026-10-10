# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence/note_shape"

RSpec.describe Sirena::Notation::PlantUML::Sequence::NoteShape do
  it "outlines rectangular notes" do
    expect(described_class.outline(:rnote, 1, 2, 3, 4))
      .to eq("M 1 2 L 4 2 L 4 6 L 1 6 Z")
  end
end
