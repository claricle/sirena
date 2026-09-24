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

    # The fix above only proves content-then-tspan survives round-tripping —
    # not genuine INTERLEAVING. A naive `body` that groups all `content`
    # before all `tspans` regardless of source order would reorder "A", "C",
    # "E" ahead of "B" and "D" here. Not reachable through sirena's own
    # renderer today (nothing constructs a `Svg::Text` with content and
    # tspans actually interleaved), but real for any future caller
    # round-tripping parsed SVG through this model.
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

    # `interleaved_body` must not treat every non-`:text` `element_order`
    # entry as a stand-in for the next parsed `<tspan>`: real mixed SVG
    # content can carry an XML comment or an element this class has no
    # attribute for. Either mistaken for "the next tspan" crashes
    # (`nil.to_xml` once `tspans` runs out) or steals a real tspan meant
    # for a later position.
    it 'skips an XML comment inside the text without crashing or losing surrounding content' do
      text = described_class.from_xml('<text>A<!-- note -->B<tspan>C</tspan></text>')

      expect(text.to_xml).to eq('<text>AB<tspan>C</tspan></text>')
    end

    it 'skips an unmapped child element without misaligning the real tspan after it' do
      text = described_class.from_xml('<text>A<foo>ignored</foo>B<tspan>C</tspan></text>')

      expect(text.to_xml).to eq('<text>AB<tspan>C</tspan></text>')
    end

    # `interleaved_body` must not assume `content`'s size still matches the
    # `:text` slots `element_order` recorded: a reassignment to a DIFFERENT
    # count (3 items against 2 recorded `:text` slots) would silently drop
    # the extra item with no error. Falls back to simple concatenation
    # instead, the same path used when there's no `element_order` at all.
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

  # `content` must stay readable through `Array(content)` regardless of
  # lutaml-model version -- see `Svg::Text#simple_body` (lib/sirena/svg/text.rb)
  # for why. Mutation-check: drop `collection: true` from `attribute :content`;
  # watched red via the `to_xml` specs above, which need `mixed: true`'s
  # collection requirement to pass.
  describe '#content' do
    it 'reads back a scalar assignment as something Array() flattens to that scalar, on any lutaml-model 0.8.x' do
      text = described_class.new
      text.content = 'plain string'

      expect(Array(text.content).join).to eq('plain string')
    end
  end
end
