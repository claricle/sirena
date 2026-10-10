# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Placement do
  let(:base) do
    { dimension: "row", ordinal: 0,
      value: Sirena::IR::Scalar.new(number: 1) }
  end

  it "accepts a complete placement" do
    expect(ir_messages(described_class, **base)).to be_empty
  end

  it "accepts a valid span" do
    span = Sirena::IR::Scalar.new(number: 2)

    expect(ir_messages(described_class, **base, span: span)).to be_empty
  end

  it "rejects a missing dimension" do
    expect(ir_messages(described_class, **base, dimension: nil))
      .to include("dimension must be a nonempty snake_case token")
  end

  it "rejects a dimension that is not snake_case" do
    expect(ir_messages(described_class, **base, dimension: "Row 1"))
      .to include("dimension must be a nonempty snake_case token")
  end

  it "rejects a missing ordinal" do
    expect(ir_messages(described_class, **base, ordinal: nil))
      .to include("ordinal must be a nonnegative Integer")
  end

  it "rejects a negative ordinal" do
    expect(ir_messages(described_class, **base, ordinal: -1))
      .to include("ordinal must be a nonnegative Integer")
  end

  it "rejects a missing value" do
    expect(ir_messages(described_class, **base, value: nil))
      .to include("value must be a valid Scalar")
  end

  it "rejects an invalid value" do
    expect(ir_messages(described_class, **base, value: Sirena::IR::Scalar.new))
      .to include("value must be a valid Scalar")
  end

  it "rejects an invalid span" do
    expect(ir_messages(described_class, **base, span: Sirena::IR::Scalar.new))
      .to include("span must be a valid Scalar")
  end
end
