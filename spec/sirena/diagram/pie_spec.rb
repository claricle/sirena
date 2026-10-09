# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Pie do
  subject(:pie) { described_class.new }

  let(:apples) { Sirena::Diagram::PieSlice.new(label: "Apples", value: 25) }
  let(:oranges) { Sirena::Diagram::PieSlice.new(label: "Oranges", value: 75) }

  describe Sirena::Diagram::PieSlice do
    subject(:slice) { described_class.new(label: "Apples", value: 25) }

    it "is valid with a label and value" do
      expect(slice.valid?).to be(true)
    end

    it "is invalid without a label" do
      slice.label = nil

      expect(slice.valid?).to be(false)
    end

    it "is invalid with an empty label" do
      slice.label = ""

      expect(slice.valid?).to be(false)
    end

    it "is invalid without a value" do
      slice.value = nil

      expect(slice.valid?).to be(false)
    end

    it "calculates its percentage of a total" do
      expect(slice.percentage(200)).to eq(12.5)
    end

    it "returns zero percent when the total is zero" do
      expect(slice.percentage(0)).to eq(0.0)
    end
  end

  it "identifies itself as a pie diagram" do
    expect(pie.diagram_type).to eq(:pie)
  end

  it "defaults to an empty, valid chart with data labels hidden" do
    expect([pie.slices, pie.show_data, pie.valid?]).to eq([[], false, true])
  end

  it "is valid when every slice is valid" do
    pie.slices = [apples, oranges]

    expect(pie.valid?).to be(true)
  end

  it "is invalid when any slice is invalid" do
    pie.slices = [apples, Sirena::Diagram::PieSlice.new(label: "", value: 75)]

    expect(pie.valid?).to be(false)
  end

  it "allows a nil slice collection for parsing" do
    pie.slices = nil

    expect(pie.valid?).to be(true)
  end

  it "sums slice values" do
    pie.slices = [apples, oranges]

    expect(pie.total_value).to eq(100.0)
  end

  it "pairs each slice with its percentage" do
    pie.slices = [apples, oranges]

    expect(pie.slices_with_percentages).to eq(
      [
        { slice: apples, percentage: 25.0 },
        { slice: oranges, percentage: 75.0 },
      ],
    )
  end

  it "reports zero percentages when the slice total is zero" do
    zero = Sirena::Diagram::PieSlice.new(label: "Nothing", value: 0)
    pie.slices = [zero]

    expect(pie.slices_with_percentages).to eq([{ slice: zero, percentage: 0.0 }])
  end

  it "calculates a slice angle from the aggregate total" do
    pie.slices = [apples, oranges]

    expect(pie.slice_angle(apples)).to eq(90.0)
  end

  it "returns a zero angle when the aggregate total is zero" do
    zero = Sirena::Diagram::PieSlice.new(label: "Nothing", value: 0)
    pie.slices = [zero]

    expect(pie.slice_angle(zero)).to eq(0.0)
  end
end
