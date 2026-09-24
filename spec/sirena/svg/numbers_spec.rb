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
    # No Sirena::Svg class has a from_xml path left to reach this sentinel
    # through parsing (sirena/02 removed the last one, Rect's, in #118) --
    # every remaining `xml do` mapping in the gem is gone. The sentinel
    # itself is still what a real parse would hand a caller, so it is built
    # directly rather than dropping the coverage.
    #
    # Diagnostic, not a fix-prover: this never calls into any of the four
    # lib files sirena/02 changes, so it stays green whether or not their
    # `xml do` deletion is reverted (mutation-check.sh confirmed this). Keep
    # it; it is the only remaining check for Numbers.read's sentinel
    # behaviour now that no Svg class can hand it one via from_xml.
    it 'has nothing to read in the sentinel lutaml leaves on a declared but unmapped attribute' do
      unset = Lutaml::Model::UninitializedClass.instance

      # Lutaml::Model::UninitializedClass is an internal name; the non-String
      # to_s result is the boundary Sirena relies on and survives a rename.
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

    # 12.0 * 1.1 is 13.200000000000001 on the way out. Measured, because the
    # obvious-looking 67.0 + (14.0 * 0.35) is exactly 71.9 and would have
    # proved nothing.
    it 'rounds off floating-point noise' do
      expect(described_class.write(12.0 * 1.1)).to eq('13.2')
    end

    # Pins the precision itself. The case above rounds to the same string at
    # any precision above three, so it proves rounding happens and not where.
    it 'rounds to four decimals' do
      expect(described_class.write(1.0 / 3)).to eq('0.3333')
    end
  end
end
