# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence/note"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Note do
  subject(:note) do
    described_class.new(shape: :note, side: :left, targets: [], text: "x")
  end

  it "attaches a targetless side note to the previous message" do
    expect(note).to be_attached
  end
end
