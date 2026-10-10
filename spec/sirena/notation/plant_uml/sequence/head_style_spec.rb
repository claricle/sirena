# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::HeadStyle do
  it "is empty without settings" do
    expect(described_class.new).to be_empty
  end

  it "is not empty with a setting" do
    expect(described_class.new(colour: "#123456")).not_to be_empty
  end
end
