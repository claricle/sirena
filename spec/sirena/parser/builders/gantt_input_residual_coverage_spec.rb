# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Gantt do
  it "normalizes single-statement hashes and ignores scalar extraction noise" do
    noise = described_class.new.apply("artifact")
    diagram = described_class.new.apply(
      title: { text: " Nested title " },
      excludes: " ",
    )

    expect([noise.sections, diagram.title, diagram.excludes]).to eq(
      [[], "Nested title", []],
    )
  end
end
