# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::DataValue do
  let(:missing_value_error) { ["value must be a valid Scalar"] }
  let(:invalid_value_errors) do
    ["scalar must contain exactly one value", *missing_value_error]
  end
  let(:empty_reference_errors) do
    [
      "dimension_id must be nonempty when present",
      "series_id must be nonempty when present",
    ]
  end

  def scalar(number = nil)
    Sirena::IR::Scalar.new(number: number)
  end

  def validation_messages(**attributes)
    described_class.new(id: "value", **attributes).validate.map(&:message)
  end

  it "reports empty optional references" do
    messages = validation_messages(
      dimension_id: "", series_id: "", value: scalar(1),
    )

    expect(messages).to eq(empty_reference_errors)
  end

  it "reports absent and invalid scalar values" do
    messages = [nil, scalar].map { |value| validation_messages(value: value) }

    expect(messages).to eq([missing_value_error, invalid_value_errors])
  end
end
