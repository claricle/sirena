# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Svg::Text do
  describe '#to_xml' do
    # `from_xml` populates `content` and `tspans` independently — nothing in
    # the `xml do` mapping enforces exclusivity between mixed text content
    # and `<tspan>` children, and ordinary mixed SVG content
    # (`<text>foo<tspan>bar</tspan></text>`) sets both. Before this fix,
    # `to_xml`'s tspans-present branch silently dropped `content`, so a
    # round-trip lost "foo". Every renderer call site is unaffected: they
    # set exactly one of `content`/`tspans`, never both.
    #
    # Mutation-check: restore the old `return` before the content line.
    # Watched red: "foo" is missing from the round-tripped XML.
    it 'round-trips mixed content and tspan children together' do
      original = '<text>foo<tspan>bar</tspan></text>'

      xml = described_class.from_xml(original).to_xml

      expect(xml).to eq(original)
    end
  end
end
