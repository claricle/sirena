# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence/note_fill"

RSpec.describe Sirena::Notation::PlantUML::Sequence::NoteFill do
  it "reads a colour name in any case" do
    expect(described_class.read("#LightBlue").colour).to eq("#ADD8E6")
  end

  it "reads a hex colour" do
    expect(described_class.read("#ff8800").colour).to eq("#FF8800")
  end

  it "reads nothing for a name it does not know" do
    expect(described_class.read("#notacolour")).to be_nil
  end

  it "reads nothing when there is no colour" do
    expect(described_class.read(nil)).to be_nil
  end
end
