# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Scalar do
  context "with exactly one typed branch" do
    subject(:results) { scalars.map { |scalar| [scalar.valid?, scalar.value] } }

    let(:scalars) do
      [
        described_class.new(text: "ready"),
        described_class.new(number: 0),
        described_class.new(boolean: false),
      ]
    end

    it "accepts exactly one typed scalar branch" do
      expect(results).to eq([[true, "ready"], [true, 0.0], [true, false]])
    end
  end

  it "rejects absent and ambiguous scalar values" do
    scalars = [described_class.new,
               described_class.new(text: "one", number: 1)]

    expect(scalars.map(&:valid?)).to eq([false, false])
  end
end
