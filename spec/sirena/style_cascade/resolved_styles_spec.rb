# frozen_string_literal: true

require 'sirena/style_cascade/resolved_styles'

RSpec.describe Sirena::StyleCascade::ResolvedStyles do
  describe '#attributed' do
    it 'reads by exact key only — a different-case key never satisfies it' do
      styles = described_class.new('FILL' => 'blue')

      expect(styles.attributed('fill')).to be_nil
    end

    it 'reads a hostile value verbatim, unvalidated — the D2 XSS contract' do
      hostile = '"><script>alert(1)</script>'
      styles = described_class.new('fill' => hostile)

      expect(styles.attributed('fill')).to eq(hostile)
    end

    it 'reads a syntactically invalid CSS value verbatim, unvalidated' do
      styles = described_class.new('fill' => 'bogus')

      expect(styles.attributed('fill')).to eq('bogus')
    end

    it 'returns nil for a key that was never declared' do
      styles = described_class.new({})

      expect(styles.attributed('fill')).to be_nil
    end

    it 'returns nil for a key declared with an empty value' do
      styles = described_class.new('fill' => '')

      expect(styles.attributed('fill')).to be_nil
    end
  end

  describe '#cascade' do
    it 'matches a property case-insensitively' do
      styles = described_class.new('FILL' => 'blue')

      expect(styles.cascade('fill')).to eq('blue')
    end

    it 'picks the LAST declared value among case variants' do
      styles = described_class.new('fill' => 'red', 'FILL' => 'blue')

      expect(styles.cascade('fill')).to eq('blue')
    end

    it 'skips an invalid value and falls back to the next most recent valid one' do
      # Ruby Hash preserves insertion order; "FILL" is inserted after
      # "fill" here, matching how the resolver's left-to-right pass would
      # have built this map.
      styles = described_class.new('fill' => 'red', 'FILL' => 'bogus')

      expect(styles.cascade('fill')).to eq('red')
    end

    it 'falls back to the raw last value verbatim when nothing validates — D2 on the bare path' do
      hostile = '"><script>alert(1)</script>'
      styles = described_class.new('fill' => hostile)

      expect(styles.cascade('fill')).to eq(hostile)
    end

    it 'returns nil for a property that was never declared under any case' do
      styles = described_class.new({})

      expect(styles.cascade('fill')).to be_nil
    end

    context 'when the value is currentColor' do
      it 'substitutes the ambient color when one is validly declared' do
        styles = described_class.new('fill' => 'currentColor', 'COLOR' => 'green')

        expect(styles.cascade('fill')).to eq('green')
      end

      it 'leaves the literal currentColor text when no ambient color is declared' do
        styles = described_class.new('fill' => 'currentColor')

        expect(styles.cascade('fill')).to eq('currentColor')
      end

      it 'excludes the exact lowercase "color" key from the ambient lookup — that is the label color' do
        styles = described_class.new('fill' => 'currentColor', 'color' => 'green')

        expect(styles.cascade('fill')).to eq('currentColor')
      end

      it 'does not resolve currentColor for a non-color property (stroke-width)' do
        styles = described_class.new('stroke-width' => 'currentColor')

        # Nonsensical CSS, but the point is only color-family properties
        # ever run ambient resolution at all.
        expect(styles.cascade('stroke-width')).to eq('currentColor')
      end

      it 'ignores an invalid ambient declaration rather than falling back to its raw text' do
        styles = described_class.new('fill' => 'currentColor', 'COLOR' => 'bogus')

        expect(styles.cascade('fill')).to eq('currentColor')
      end
    end
  end

  describe '#label_color' do
    it 'reads the literal lowercase "color" key only' do
      styles = described_class.new('color' => 'green')

      expect(styles.label_color).to eq('green')
    end

    it 'never matches a different-case "color" key — that one is a box style' do
      styles = described_class.new('COLOR' => 'green')

      expect(styles.label_color).to be_nil
    end

    it 'returns nil when no label color was declared' do
      styles = described_class.new({})

      expect(styles.label_color).to be_nil
    end
  end
end
