# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::StateDiagram do
  it "ignores a scalar extraction artifact" do
    diagram = described_class.new.apply("noise")

    expect([diagram.states, diagram.transitions, diagram.direction])
      .to eq([[], [], nil])
  end
end
