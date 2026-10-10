# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Timeline do
  it "ignores an empty transformed task" do
    diagram = described_class.new.apply(task: "   ")

    expect([diagram.events, diagram.sections]).to eq([[], []])
  end
end
