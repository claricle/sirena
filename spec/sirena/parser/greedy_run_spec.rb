# frozen_string_literal: true

require 'spec_helper'
require 'parslet'
require 'sirena/parser/atoms/greedy_run'

RSpec.describe Sirena::Parser::Atoms::GreedyRun do
  let(:atom) { described_class.new('[a-z]') }

  describe '#try' do
    it 'matches a variable-length run in the input' do
      tree = atom.parse('abcxyz')

      expect(tree.to_s).to eq('abcxyz')
    end

    it "fails cleanly when min: 1 (the default) sees no matching character" do
      expect { described_class.new('[a-z]').parse('123') }.to raise_error(Parslet::ParseFailed)
    end

    it 'matches only at the current position, never further along' do
      expect { described_class.new('[a-z]').parse('12ab', prefix: true) }
        .to raise_error(Parslet::ParseFailed)
    end

    it 'matches empty when min: 0 and no character matches' do
      tree = described_class.new('[a-z]', min: 0).parse('')

      expect(tree.to_s).to eq('')
    end

    it 'consumes a run longer than one chunk in more than one chunk without losing characters' do
      long_run = 'a' * 120_000
      tree = atom.parse(long_run)

      expect(tree.to_s).to eq(long_run)
      expect(tree.to_s.length).to eq(120_000)
    end

    # Measured at position 0, an empty (unscanned) line cache and the
    # real one agree ([1, 1]), so a slice built with the wrong cache
    # would pass this test for the wrong reason. Starting after a real
    # newline makes them disagree: an empty cache assumes no newlines
    # exist at all and reports [1, 3].
    it 'carries a real line cache, not a missing one, on the returned slice' do
      tree = (Parslet.str("x\n") >> atom.as(:r)).parse("x\nab")

      expect(tree[:r].line_and_column).to eq([2, 1])
    end
  end

  describe '.scan' do
    it 'scans an anchored pattern directly, joining chunks into one string' do
      source = Parslet::Source.new('a' * 70_000)
      anchored = Regexp.new('\A(?:[a-z])*', Regexp::MULTILINE)

      matched = described_class.scan(source, anchored)

      expect(matched.length).to eq(70_000)
      expect(source.chars_left).to eq(0)
    end

    it 'rewinds the source to just past the matched run' do
      source = Parslet::Source.new('abc123')
      anchored = Regexp.new('\A(?:[a-z])*', Regexp::MULTILINE)

      matched = described_class.scan(source, anchored)

      expect(matched).to eq('abc')
      expect(source.consume(3).to_s).to eq('123')
    end

    # `\u00A0` gives `anchored` a fixed UTF-8 encoding. Matching it against
    # an ASCII-8BIT source with a byte >= 0x80 used to raise
    # `Encoding::CompatibilityError` straight out of `Regexp#match` instead
    # of failing to match, crashing the whole parse.
    it 'keeps the compatible run before an encoding-incompatible byte instead of raising' do
      source = Parslet::Source.new((+"ab\xFFcd").force_encoding(Encoding::ASCII_8BIT))
      anchored = Regexp.new('\A(?:[^~\u00A0])*', Regexp::MULTILINE)

      matched = described_class.scan(source, anchored)

      expect(matched).to eq('ab')
      expect(source.chars_left).to eq(3)
    end

    # The kept prefix must be the same regardless of which doubling-probe
    # chunk the incompatible byte lands in (probe starts at 64, doubles
    # each round) -- the fix must not depend on the chunk boundary.
    [30, 64, 100, 130, 200].each do |ascii_run_length|
      it "keeps a #{ascii_run_length}-byte compatible run wherever the incompatible byte falls" do
        prefix = 'a' * ascii_run_length
        source = Parslet::Source.new("#{prefix}\xFF".force_encoding(Encoding::ASCII_8BIT))
        anchored = Regexp.new('\A(?:[^~\u00A0])*', Regexp::MULTILINE)

        matched = described_class.scan(source, anchored)

        expect(matched).to eq(prefix)
        expect(source.chars_left).to eq(1)
      end
    end
  end

  describe '#to_s_inner' do
    # A Sequence sibling's error message renders the WHOLE sequence via
    # `#to_s`, including atoms that did not themselves fail -- so this
    # needs to survive being called even when this atom's own match
    # succeeded.
    it 'renders without raising' do
      expect { atom.to_s }.not_to raise_error
      expect(atom.to_s).to include('a-z')
    end
  end
end
