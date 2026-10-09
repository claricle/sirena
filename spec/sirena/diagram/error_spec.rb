# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Error do
  subject(:diagram) { described_class.new }

  it "identifies itself as an error diagram" do
    expect(diagram.diagram_type).to eq(:error)
  end

  it "is valid without a message" do
    expect(diagram).to be_valid
  end

  it "coerces messages to strings" do
    expect(described_class.new(message: 404).message).to eq("404")
  end
end
