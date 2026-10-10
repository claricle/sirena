# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/builders/quadrant"

RSpec.describe Sirena::Parser::Builders::Quadrant do
  subject(:builder) { described_class.new }

  it "ignores a scalar extraction artifact" do
    diagram = builder.apply("artifact")

    expect([diagram.title, diagram.points]).to eq([nil, []])
  end

  it "uses the value from a hash-wrapped title" do
    diagram = builder.apply([{ title: { other: "Fallback title" } }])

    expect(diagram.title).to eq("Fallback title")
  end
end
