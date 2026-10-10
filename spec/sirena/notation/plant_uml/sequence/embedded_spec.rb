# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Embedded do
  it "reads the body between the braces" do
    expect(described_class.read("{{\nA -> B\n}}").body).to eq("A -> B")
  end

  it "reads a leading scale and leaves it out of the body" do
    embedded = described_class.read("{{\nscale 0.5\nA -> B\n}}")

    expect([embedded.scale, embedded.body]).to eq([0.5, "A -> B"])
  end

  it "scales by one when none is written" do
    expect(described_class.read("{{\nA -> B\n}}").scale).to eq(1.0)
  end

  it "is nil for text beside the block" do
    expect(described_class.read("hi\n{{\nA -> B\n}}")).to be_nil
  end

  it "is nil for two blocks" do
    expect(described_class.read("{{\nA -> B\n}}\n{{\nC -> D\n}}")).to be_nil
  end

  it "is nil for plain text" do
    expect(described_class.read("hello")).to be_nil
  end

  it "keeps a nested block inside the body" do
    embedded = described_class.read("{{\n{{\nA -> B\n}}\n}}")

    expect(embedded.body).to eq("{{\nA -> B\n}}")
  end
end
