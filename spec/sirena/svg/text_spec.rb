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

    # Round 3 Codex High: the fix above only proved content-then-tspan
    # survives round-tripping — it never proved genuine INTERLEAVING does.
    # Before this fix, `to_xml` grouped all plain-text `content` before all
    # `tspans` regardless of source order: this input round-tripped as
    # `<text>ACE<tspan>B</tspan><tspan>D</tspan></text>`, silently
    # reordering "A", "C" and "E" ahead of "B" and "D". Not reachable
    # through sirena's own renderer today (confirmed across two review
    # rounds: nothing here constructs a `Svg::Text` with both content and
    # tspans interleaved — always one or the other), but real should any
    # future caller round-trip parsed SVG through this model.
    #
    # Mutation-check: revert `body` to the old
    # `Escaping.escape_text(Array(content).join) +
    # Array(tspans).map(&:to_xml).join` unconditionally. Watched red: "A",
    # "C", "E" come back concatenated ahead of both tspans instead of
    # interleaved with them.
    it 'preserves true document order for genuinely interleaved content and tspans' do
      original = '<text>A<tspan>B</tspan>C<tspan>D</tspan>E</text>'

      xml = described_class.from_xml(original).to_xml

      expect(xml).to eq(original)
    end
  end
end
