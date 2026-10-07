# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::Parsed do
  subject(:parsed) do
    described_class.new(type: :pie, diagram: :model,
                        transform: :transform_class, renderer: :renderer_class)
  end

  it "reads back each keyword it was built with" do
    expect(parsed).to have_attributes(
      type: :pie, diagram: :model,
      transform: :transform_class, renderer: :renderer_class
    )
  end

  it "requires every keyword" do
    expect { described_class.new(type: :pie, diagram: :model) }
      .to raise_error(ArgumentError, /missing keywords?: :transform, :renderer/)
  end

  it "refuses positional arguments" do
    expect { described_class.new(:pie, :model, :transform, :renderer) }
      .to raise_error(ArgumentError)
  end

  it "is frozen once built" do
    expect(parsed).to be_frozen
  end

  it "has no writers" do
    expect(parsed.public_methods(false)).not_to include(:type=, :diagram=)
  end
end
