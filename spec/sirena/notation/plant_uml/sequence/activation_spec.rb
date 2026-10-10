# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Activation do
  it "recognizes an opening phase" do
    expect(described_class.new(participant: "A", phase: :on)).to be_on
  end

  it "does not recognize a closing phase" do
    expect(described_class.new(participant: "A", phase: :off)).not_to be_on
  end
end
