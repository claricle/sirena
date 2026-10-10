# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Model do
  it "rejects a non-hash attributes argument" do
    expect { described_class.new([]) }
      .to raise_error(ArgumentError, "attributes must be a Hash")
  end

  it "rejects non-string and non-symbol attribute names" do
    expect { described_class.new(1 => "value") }
      .to raise_error(
        ArgumentError,
        "attribute names must be Strings or Symbols",
      )
  end

  it "rejects attribute names duplicated after normalization" do
    attributes = { "field" => "first", field: "second" }

    expect { described_class.new(attributes) }
      .to raise_error(ArgumentError, "duplicate attribute names")
  end
end
