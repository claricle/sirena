# frozen_string_literal: true

require 'sirena/style_cascade/resolver'

RSpec.describe Sirena::StyleCascade::Resolver do
  describe '#resolve' do
    # Step: comma-split. `styles2Map`'s input is already a comma-split
    # array in real mermaid; sirena stores one raw declaration string per
    # class, so splitting on "," is this pipeline's first real step.
    it 'splits one class declaration on commas into separate chunks' do
      resolver = described_class.new({ 'a' => 'fill:#f96,stroke:#333' })

      styles = resolver.resolve(['a'])

      expect(styles.attributed('fill')).to eq('#f96')
      expect(styles.attributed('stroke')).to eq('#333')
    end

    # Step: color replay (`ErDB#addClass`'s textStyles mechanism). Any
    # chunk whose text contains "color" is replayed a second time at the
    # end of its class's declarations, so it outranks a later same-key
    # chunk that does not contain "color" — verified against mermaid:
    # `classDef a stroke:currentcolor,stroke:red` resolves to
    # `currentcolor`, not `red`.
    it 'replays a color-bearing chunk after the rest of its class, so it wins a later same-key chunk' do
      resolver = described_class.new({ 'a' => 'stroke:currentcolor,stroke:red' })

      styles = resolver.resolve(['a'])

      expect(styles.attributed('stroke')).to eq('currentcolor')
    end

    # The replay is RENAMED ("fill" -> "bgFill" in the replayed copy only)
    # specifically so it cannot clobber a LEGITIMATE later same-key
    # write. `fill` declared twice, with the first occurrence
    # color-bearing, is the case that distinguishes a renamed replay from
    # an unrenamed one — verified against a real mmdc render: mermaid
    # computes fill="blue" here, not "currentcolor".
    it 'lets a later legitimate "fill" declaration win over an earlier color-bearing "fill" one' do
      resolver = described_class.new({ 'a' => 'fill:currentcolor,fill:blue' })

      styles = resolver.resolve(['a'])

      expect(styles.attributed('fill')).to eq('blue')
    end

    it 'does not replay a chunk that never mentions "color"' do
      resolver = described_class.new({ 'a' => 'stroke:red,stroke:blue' })

      styles = resolver.resolve(['a'])

      # No replay in play: plain left-to-right, last chunk wins.
      expect(styles.attributed('stroke')).to eq('blue')
    end

    # Step: merge classes. Every entity implicitly carries the "default"
    # class ahead of whatever it was explicitly assigned.
    it 'prepends the implicit "default" class even when nothing was assigned' do
      resolver = described_class.new({ 'default' => 'fill:#f9f9f9' })

      styles = resolver.resolve([])

      expect(styles.attributed('fill')).to eq('#f9f9f9')
    end

    it 'lets an explicitly assigned class override the default class on a shared property' do
      resolver = described_class.new(
        {
          'default' => 'fill:#f9f9f9',
          'a' => 'fill:red'
        }
      )

      styles = resolver.resolve(['a'])

      expect(styles.attributed('fill')).to eq('red')
    end

    it 'silently contributes nothing for an assigned class with no matching classDef' do
      resolver = described_class.new({})

      styles = resolver.resolve(['never-declared'])

      expect(styles.attributed('fill')).to be_nil
    end

    # Step: merge classes, NOT deduped — a repeated class assignment moves
    # that class's declarations to the end and lets it win a later
    # conflict. Verified against mermaid: `CAR:::a,b` then `CAR:::a`
    # resolves `fill:red` (the trailing "a"), not `fill:blue`.
    it 'compiles a repeated class twice, and the trailing occurrence wins a tie' do
      resolver = described_class.new(
        {
          'a' => 'fill:red',
          'b' => 'fill:blue'
        }
      )

      styles = resolver.resolve(%w[a b a])

      expect(styles.attributed('fill')).to eq('red')
    end

    # Step: build the exact-case map (`styles2Map`). Unlimited split on
    # ":", keep only the first two parts — a third colon-separated segment
    # is silently dropped, not folded into the value.
    it 'keeps only the first two colon-separated parts of a chunk' do
      resolver = described_class.new({ 'a' => 'fill:red:blue' })

      styles = resolver.resolve(['a'])

      expect(styles.attributed('fill')).to eq('red')
    end

    it 'never folds case — "fill" and "FILL" are distinct keys' do
      resolver = described_class.new({ 'a' => 'fill:red,FILL:blue' })

      styles = resolver.resolve(['a'])

      # Attributed (exact-key) reads only the literal lowercase "fill".
      expect(styles.attributed('fill')).to eq('red')
    end

    it 'lets a later value-clearing declaration ("fill:") actually clear an earlier one' do
      # `"fill:".split(':', -1)` gives `["fill", ""]`, so this chunk DOES
      # create a "fill" entry (with an empty value, later read as absent
      # by `ResolvedStyles#attributed`'s `present` filter) that overwrites
      # the earlier "fill:red". Ruby's default split (no -1 limit) would
      # instead drop the trailing empty field, giving `["fill"]` — which
      # `mermaid_split` reads as "no colon at all" and SKIPS, silently
      # leaving the earlier "fill:red" in place. This example is the one
      # that tells the two apart: without `-1`, this would read back
      # "red", not nil.
      resolver = described_class.new({ 'a' => 'fill:red,fill:' })

      styles = resolver.resolve(['a'])

      expect(styles.attributed('fill')).to be_nil
    end
  end
end
