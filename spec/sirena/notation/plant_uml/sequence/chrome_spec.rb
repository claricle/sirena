# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Chrome do
  it "returns configured text by kind" do
    chrome = described_class.new({ header: "Status" })
    expect(chrome.text(:header)).to eq("Status")
  end
end
