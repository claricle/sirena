# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Chrome do
  it "returns configured text by kind" do
    expect(described_class.new({ header: "Status" }).text(:header)).to eq("Status")
  end
end
