# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Radar do
  subject(:layout) { described_class.new }

  let(:source) { "radar-beta\n  axis a, b, c\n  curve c1{1, 2, 3}\n" }
  let(:diagram) { Sirena::Parser::Radar.new.parse(source) }

  describe "#call" do
    let(:data) do
      Sirena::Notation::Mermaid::IRAdapters::Radar.call(diagram).tap do |ir|
        missing = ir.dimensions[1].id
        ir.values = ir.values.reject do |entry|
          entry.role == "measurement" && entry.dimension_id == missing
        end
      end
    end

    it "reads a measurement that is absent from the data as zero" do
      expect(layout.call(data).curves.first.points.map(&:value))
        .to eq([1.0, 0.0, 3.0])
    end

    it "draws an empty curve path when the chart has no axes" do
      empty = Sirena::Diagram::Radar.new
      empty.curves = [Sirena::Diagram::RadarCurve.new("lonely")]

      expect(layout.call(empty).curves.first.path_data).to eq("")
    end
  end

  # normalize_value is unreachable through #call because the value range is
  # always widened first; this pins its own degenerate-range answer.
  describe "#normalize_value" do
    it "maps every value to zero when the range is a single point" do
      expect(layout.send(:normalize_value, 5, 3, 3)).to eq(0)
    end
  end
end
