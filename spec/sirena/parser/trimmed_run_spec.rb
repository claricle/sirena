# frozen_string_literal: true

require 'spec_helper'
require 'parslet'
require 'sirena/parser/atoms/trimmed_run'

RSpec.describe Sirena::Parser::Atoms::TrimmedRun do
  let(:atom) { described_class.new('[-.\/\w]', '[.\/]') }

  describe '#try' do
    it 'keeps the whole run when it already ends in the narrow class' do
      tree = atom.parse('release/1.0.0')

      expect(tree.to_s).to eq('release/1.0.0')
    end

    it 'trims one trailing dot, leaving it for the next atom' do
      tree = (atom.as(:name) >> Parslet.str('.')).parse('foo.')

      expect(tree[:name].to_s).to eq('foo')
    end

    it 'trims a run of several trailing dots and slashes' do
      tree = (atom.as(:name) >> Parslet.str('../')).parse('foo../')

      expect(tree[:name].to_s).to eq('foo')
    end

    it 'matches empty when the whole run is outside the narrow class' do
      tree = (atom.as(:name) >> Parslet.str('.')).parse('.')

      expect(tree[:name].to_s).to eq('')
    end

    it 'matches empty at end of input' do
      expect(atom.parse('').to_s).to eq('')
    end

    # Crosses the 50_000-char chunk ceiling the underlying `GreedyRun`
    # uses, confirming `TrimmedRun`'s own trimming stays correct on
    # either side of a chunk split, not just within a single chunk.
    it 'stays correct when the run crosses the internal chunk boundary' do
      long_run = "#{'a' * 49_999}.#{'b' * 10}"
      tree = atom.parse(long_run)

      expect(tree.to_s).to eq(long_run)
    end

    it 'trims correctly when the trailing dot sits right at the chunk boundary' do
      long_run = "#{'a' * 50_000}."
      tree = (atom.as(:name) >> Parslet.str('.')).parse(long_run)

      expect(tree[:name].to_s).to eq('a' * 50_000)
    end
  end

  describe '#to_s_inner' do
    it 'renders the underlying run pattern and the trim class' do
      expect(atom.to_s).to eq('/\A(?:[-.\/\w])*/m(trim: /(?:[.\/])*\z/)')
    end
  end
end
