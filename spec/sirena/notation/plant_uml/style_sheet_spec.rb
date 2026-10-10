# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/style_sheet"

RSpec.describe Sirena::Notation::PlantUML::StyleSheet do
  subject(:sheet) { described_class.new(rules: { title: { size: 20 } }) }

  it "returns a configured rule" do
    expect(sheet.rule(:title)).to eq(size: 20)
  end

  it "returns an empty rule for an absent kind" do
    expect(sheet.rule(:footer)).to eq({})
  end
end
