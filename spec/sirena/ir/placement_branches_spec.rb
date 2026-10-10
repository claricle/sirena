# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Placement do
  let(:dimension_error) { ["dimension must be a nonempty snake_case token"] }
  let(:ordinal_error) { ["ordinal must be a nonnegative Integer"] }
  let(:value_error) { ["value must be a valid Scalar"] }
  let(:invalid_value_errors) do
    ["scalar must contain exactly one value", *value_error]
  end
  let(:invalid_span_errors) do
    ["scalar must contain exactly one value", "span must be a valid Scalar"]
  end

  def scalar(number = nil)
    Sirena::IR::Scalar.new(number: number)
  end

  def messages_for(**attributes)
    described_class.new(**attributes).validate.map(&:message)
  end

  def dimension_messages(dimension)
    messages_for(dimension: dimension, ordinal: 0, value: scalar(1))
  end

  def ordinal_messages(ordinal)
    messages_for(dimension: "column", ordinal: ordinal, value: scalar(1))
  end

  def value_messages(value)
    messages_for(dimension: "column", ordinal: 0, value: value)
  end

  it "reports absent and malformed dimensions" do
    messages = [nil, "Grid Column"].map { |value| dimension_messages(value) }

    expect(messages).to eq([dimension_error, dimension_error])
  end

  it "reports absent and negative ordinals" do
    messages = [nil, -1].map { |value| ordinal_messages(value) }

    expect(messages).to eq([ordinal_error, ordinal_error])
  end

  it "reports absent and invalid scalar values" do
    messages = [nil, scalar].map { |value| value_messages(value) }

    expect(messages).to eq([value_error, invalid_value_errors])
  end

  it "reports an invalid optional span" do
    messages = messages_for(
      dimension: "column", ordinal: 0, value: scalar(1), span: scalar,
    )

    expect(messages).to eq(invalid_span_errors)
  end
end
