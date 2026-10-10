# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassNote do
  it "keeps an empty input as one renderable line" do
    expect(described_class.lines_of(nil)).to eq([""])
  end
end
