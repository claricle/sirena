# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/builders/architecture"

RSpec.describe Sirena::Parser::Builders::Architecture do
  it "ignores a scalar extraction artifact" do
    diagram = described_class.new.apply("artifact")
    actual = [
      diagram.title, diagram.groups, diagram.services,
      diagram.junctions, diagram.edges
    ]

    expect(actual).to eq([nil, [], [], [], []])
  end
end
