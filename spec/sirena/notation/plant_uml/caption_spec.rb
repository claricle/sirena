# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Caption do
  it "accepts plain text" do
    expect(described_class.plain?("plain caption")).to be(true)
  end

  it "rejects an arrow-like line" do
    expect(described_class.plain?("A -> B")).to be(false)
  end
end
