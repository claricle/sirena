# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::DataValue do
  let(:scalar) { Sirena::IR::Scalar.new(number: 1) }

  it "accepts a value with a valid scalar" do
    expect(ir_messages(described_class, id: "v", value: scalar)).to be_empty
  end

  it "rejects an empty dimension reference" do
    expect(ir_messages(described_class, id: "v", value: scalar,
                                        dimension_id: ""))
      .to include("dimension_id must be nonempty when present")
  end

  it "rejects an empty series reference" do
    expect(ir_messages(described_class, id: "v", value: scalar,
                                        series_id: ""))
      .to include("series_id must be nonempty when present")
  end

  it "rejects a missing value" do
    expect(ir_messages(described_class, id: "v"))
      .to include("value must be a valid Scalar")
  end

  it "rejects an invalid scalar" do
    expect(ir_messages(described_class, id: "v",
                                        value: Sirena::IR::Scalar.new))
      .to include("value must be a valid Scalar")
  end
end
