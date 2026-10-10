# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::JsNumber do
  it "keeps every significant digit in exponential notation" do
    expect(described_class.stringify(1.23e-7)).to eq("1.23e-7")
  end
end
