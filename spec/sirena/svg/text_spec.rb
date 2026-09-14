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

    # Codex round 3 High: `interleaved_body` used to replay `node.text_content`
    # straight off the frozen `element_order` snapshot `from_xml` captured,
    # instead of reading the model's current `content`. Any later mutation of
    # `content` on a parsed instance was silently invisible to `to_xml` —
    # confirmed directly: assigning new `content` after `from_xml` left
    # `to_xml` re-emitting the original parsed text unchanged.
    #
    # Mutation-check: revert `interleaved_body` to read `node.text_content`
    # instead of shifting from a `content` queue. Watched red: the
    # reassigned text never appears in the output.
    it 'reflects a content mutation made after from_xml' do
      text = described_class.from_xml('<text>A<tspan>B</tspan>C</text>')
      text.content = %w[X Y]

      expect(text.to_xml).to eq('<text>X<tspan>B</tspan>Y</text>')
    end

    # Codex round 3 Medium: `interleaved_body` treated every non-`:text`
    # `element_order` entry as a stand-in for the next parsed `<tspan>`.
    # Real mixed SVG content can carry an XML comment inside `<text>`
    # (`node_type == :comment`) or, more subtly, an element that is not a
    # `tspan` at all — neither is tracked by any attribute this class
    # declares, so treating either as "the next tspan" either crashes
    # (`nil.to_xml` once `tspans` runs out) or silently steals a real
    # tspan meant for a later position. Reproduced directly before this
    # fix: a comment raised `NoMethodError`, and an interleaved unmapped
    # `<foo>` element consumed the one real `<tspan>` ahead of it, leaving
    # it later with nothing to shift.
    #
    # Mutation-check: replace the `node.name == 'tspan'` guard with a bare
    # `node.node_type == :element`. Watched red: this example raises
    # `NoMethodError` on the comment case below it in the same run.
    it 'skips an XML comment inside the text without crashing or losing surrounding content' do
      text = described_class.from_xml('<text>A<!-- note -->B<tspan>C</tspan></text>')

      expect(text.to_xml).to eq('<text>AB<tspan>C</tspan></text>')
    end

    it 'skips an unmapped child element without misaligning the real tspan after it' do
      text = described_class.from_xml('<text>A<foo>ignored</foo>B<tspan>C</tspan></text>')

      expect(text.to_xml).to eq('<text>AB<tspan>C</tspan></text>')
    end

    # Codex round 4 Medium: `interleaved_body` (and the mutation spec just
    # above proving it reflects a same-count reassignment) both assumed
    # `content`'s size still matches the `:text` slots `element_order`
    # recorded. A reassignment to a DIFFERENT count breaks that: before
    # this fix, 3 items replayed against 2 `:text` slots shifted "X" and
    # "Y" into the two slots and silently dropped "Z" — no error, no
    # indication anything was lost. Falls back to the same simple
    # concatenation used when there's no `element_order` at all, rather
    # than replay a mapping already known not to fit.
    #
    # Mutation-check: delete the `cardinality_matches?` guard in
    # `interleaved_body`. Watched red: "Z" goes missing from the output.
    it "falls back to simple concatenation when a reassignment does not match element_order's recorded count" do
      text = described_class.from_xml('<text>A<tspan>B</tspan>C</text>')
      text.content = %w[X Y Z]

      expect(text.to_xml).to eq('<text>XYZ<tspan>B</tspan></text>')
    end

    it 'falls back to simple concatenation when tspans shrink below element_order\'s recorded count too' do
      text = described_class.from_xml('<text>A<tspan>B</tspan>C<tspan>D</tspan>E</text>')
      text.tspans = [Sirena::Svg::Tspan.new.tap { |t| t.content = 'Z' }]

      expect(text.to_xml).to eq('<text>ACE<tspan>Z</tspan></text>')
    end
  end
end
