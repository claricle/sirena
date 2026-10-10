# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Gantt do
  let(:noise) { described_class.new.apply("artifact") }
  let(:diagram) do
    described_class.new.apply(
      title: { text: " Nested title " },
      excludes: " ",
    )
  end

  it "normalizes single-statement hashes and ignores scalar extraction noise" do
    expect([noise.sections, diagram.title, diagram.excludes]).to eq(
      [[], "Nested title", []],
    )
  end
end
