# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence/text_advances"

RSpec.describe Sirena::Notation::PlantUML::Sequence::TextAdvances do
  it "matches the pinned PlantUML plain sans-serif advances" do
    expect(described_class.width("transparent_keyword", font_size: 14))
      .to be_within(0.0001).of(142.7412)
  end

  it "matches the pinned PlantUML bold sans-serif advances" do
    expect(described_class.width("Alice", font_size: 26, bold: true))
      .to be_within(0.0001).of(65.127)
  end

  it "measures the widest explicit line instead of summing them" do
    expect(described_class.width("longest\\nshort", font_size: 13))
      .to be_within(0.0001).of(46.6489)
  end
end
