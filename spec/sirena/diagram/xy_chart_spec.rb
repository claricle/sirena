# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::XYDataset do
  subject(:dataset) { described_class.new("sales") }

  it "coerces every value to Float when assigned in bulk" do
    dataset.values = [1, "2.5", 3r]

    expect(dataset.values).to eq([1.0, 2.5, 3.0])
  end

  it "coerces a value added one at a time" do
    dataset.add_value("4")

    expect(dataset.values).to eq([4.0])
  end
end
