# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Svg::Numbers do
  describe '.read' do
    it 'reads a float straight through' do
      expect(described_class.read(14.0)).to eq(14.0)
    end

    it 'reads a number written as a string, which is how renderers set them' do
      expect(described_class.read('0.3')).to eq(0.3)
    end

    it 'reads the number in front of a unit' do
      expect(described_class.read('14px')).to eq(14.0)
    end

    it 'reads a signed and exponent-bearing number' do
      expect(described_class.read('-1.5e2')).to eq(-150.0)
    end

    it 'has nothing to read in nil' do
      expect(described_class.read(nil)).to be_nil
    end

    it 'has nothing to read in a value that is not a number' do
      expect(described_class.read('inherit')).to be_nil
    end

    # lutaml-model leaves an unset attribute holding a sentinel that answers
    # to_s with itself, so a plain to_f would have turned it into 0.0 and
    # every unset attribute would have been emitted as zero.
    #
    # Parsed in, not built: `Rect.new.style` is plain nil, so writing it that
    # way asks the same question as the nil case above and never reaches the
    # sentinel at all. `style` because only an attribute the class does NOT
    # map is left holding the sentinel, and every mapped one is set to nil
    # by the parse.
    it 'has nothing to read in an attribute lutaml never set' do
      unset = Sirena::Svg::Text.from_xml('<text>x</text>').style

      # Lutaml::Model::UninitializedClass is an internal name; the non-String
      # to_s result is the boundary Sirena relies on and survives a rename.
      expect(unset).not_to be_nil
      expect(unset.to_s).not_to be_a(String)
      expect(described_class.read(unset)).to be_nil
    end
  end

  describe '.write' do
    it 'keeps a clean number clean' do
      expect(described_class.write(71.9)).to eq('71.9')
    end

    it 'keeps the .0 suffix on a whole float' do
      expect(described_class.write(10.0)).to eq('10.0')
    end

    # 67.0 + (14.0 * 0.35) is 71.89999999999999 on the way out.
    it 'rounds off floating-point noise' do
      expect(described_class.write(67.0 + (14.0 * 0.35))).to eq('71.9')
    end

    # Pins the precision itself. The case above rounds to the same string at
    # any precision above three, so it proves rounding happens and not where.
    it 'rounds to four decimals' do
      expect(described_class.write(1.0 / 3)).to eq('0.3333')
    end
  end
end
