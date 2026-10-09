# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Data do
  def value(id, dimension_id: nil, series_id: nil, scalar: 0)
    Sirena::IR::DataValue.new(
      id: id, dimension_id: dimension_id, series_id: series_id,
      value: Sirena::IR::Scalar.new(number: scalar)
    )
  end

  context "with ordered chart content" do
    subject(:ir) do
      described_class.new(
        id: "chart",
        dimensions: [Sirena::IR::Dimension.new(id: "x")],
        series: [Sirena::IR::Series.new(id: "current")],
        values: [value("v1", dimension_id: "x", series_id: "current")],
        items: [Sirena::IR::Item.new(id: "caption", label: "Quarterly")],
      )
    end

    it "preserves ordered dimensions, series, values, and content" do
      expect([ir.valid?, ir.dimensions.map(&:id), ir.series.map(&:id),
              ir.values.map(&:id), ir.items.map(&:id)])
        .to eq([true, ["x"], ["current"], ["v1"], ["caption"]])
    end
  end

  context "with a cross-collection duplicate" do
    subject(:ir) do
      described_class.new(
        id: "chart",
        dimensions: [Sirena::IR::Dimension.new(id: "same")],
        series: [Sirena::IR::Series.new(id: "same")],
      )
    end

    it "rejects duplicate identities across all collections" do
      expect(ir).not_to be_valid
    end
  end

  context "with unknown value references" do
    subject(:results) do
      values = [value("dimension", dimension_id: "missing"),
                value("series", series_id: "missing")]
      values.map do |entry|
        described_class.new(id: "chart", values: [entry]).valid?
      end
    end

    it "rejects unknown dimension and series references" do
      expect(results).to eq([false, false])
    end
  end

  it "allows values without dimension or series references" do
    ir = described_class.new(id: "content", values: [value("standalone")])

    expect(ir).to be_valid
  end

  context "with invalid containment" do
    subject(:results) { [unresolved.valid?, cycle.valid?] }

    let(:unresolved) do
      described_class.new(
        id: "chart", items: [Sirena::IR::Item.new(
          id: "a", parent_id: "missing",
        )]
      )
    end
    let(:cycle) do
      described_class.new(
        id: "chart",
        items: [Sirena::IR::Item.new(id: "a", parent_id: "b"),
                Sirena::IR::Item.new(id: "b", parent_id: "a")],
      )
    end

    it "rejects unresolved and cyclic containment" do
      expect(results).to eq([false, false])
    end
  end

  it "has no connectivity surface" do
    expect(described_class.attributes.keys & %i[edges source_id target_id])
      .to be_empty
  end
end
