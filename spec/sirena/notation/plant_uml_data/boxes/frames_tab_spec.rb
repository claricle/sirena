# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUMLData::Boxes::Frames do
  let(:frame) do
    described_class::Frame.new(name: "task", x: 10.0, y: 20.0, width: 200.0,
                               height: 100.0)
  end
  let(:tab) do
    described_class.marks(frame).find { |mark| mark[:kind] == :polygon }
  end

  it "leans the right edge of a tab down its whole height, as the JAR does" do
    expect(tab[:points].map { |point| point[1] }.uniq).to eq([20.0, 42.0])
  end

  it "draws the tab as four corners" do
    expect(tab[:points].size).to eq(4)
  end
end
