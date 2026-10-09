# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::JsNumber do
  def stringify_all(values)
    values.map { |value| described_class.stringify(value) }
  end

  describe ".stringify" do
    it "preserves JavaScript spellings for non-finite numbers and zero" do
      values = [Float::NAN, Float::INFINITY, -Float::INFINITY, 0.0, -0.0]

      expect(stringify_all(values)).to eq(%w[NaN Infinity -Infinity 0 0])
    end

    it "places the decimal point without unnecessary zeroes" do
      values = [-12.5, 123.45, 0.00123]

      expect(stringify_all(values)).to eq(%w[-12.5 123.45 0.00123])
    end

    it "uses JavaScript exponential thresholds" do
      values = [1e-6, 1e-7, 1e20, 1e21]

      expected = %w[0.000001 1e-7 100000000000000000000 1e+21]

      expect(stringify_all(values)).to eq(expected)
    end

    it "rounds integers through their JavaScript double representation" do
      expect(described_class.stringify(9_007_199_254_740_993))
        .to eq("9007199254740992")
    end
  end
end
