# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Parser do
  include PlantUmlSequenceTitleHelpers

  it "reads the title" do
    expect(parsed_diagram("title Hello there", "A -> B").title)
      .to eq("Hello there")
  end

  it "has no title when none is written" do
    expect(parsed_diagram("A -> B").title).to be_nil
  end

  it "refuses a title with markup" do
    expect(refusal_for("title **T**", "A -> B"))
      .to have_attributes(construct: "title")
  end

  it "keeps a participant called title" do
    expect(parsed_diagram("title -> B : x").messages.size).to eq(1)
  end
end
