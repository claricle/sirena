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

    # The underlying `GreedyRun` reads in chunks of 64, 128, 256, ...
    # characters, so its chunk edges fall at the cumulative sums 64, 192,
    # 448, ... A dot at run index `edge - 1` is the last character of a
    # chunk; at `edge` it is the first of the next. `TrimmedRun`'s own trim
    # step must stay correct on either side of each edge. These are the
    # first three edges; git_graph_spec.rb walks every edge through the
    # switch to 50_000-character chunks.
    [64, 192, 448].each do |edge|
      context "with the #{edge}-character chunk edge" do
        [edge - 1, edge].each do |dot_index|
          it "keeps a dot at index #{dot_index} followed by more run" do
            run = "#{'a' * dot_index}.#{'b' * 10}"

            expect(atom.parse(run).to_s).to eq(run)
          end

          it "trims a trailing dot at index #{dot_index}" do
            named = atom.as(:name) >> Parslet.str(".")
            tree = named.parse("#{'a' * dot_index}.")

            expect(tree[:name].to_s).to eq("a" * dot_index)
          end
        end

        it "trims trailing dots that straddle the edge" do
          named = atom.as(:name) >> Parslet.str("..")
          tree = named.parse("#{'a' * (edge - 1)}..")

          expect(tree[:name].to_s).to eq("a" * (edge - 1))
        end
      end
    end
  end

  describe '#to_s_inner' do
    it 'renders the underlying run pattern and the trim class' do
      expect(atom.to_s).to eq('/\A(?:[-.\/\w])*/m(trim: /(?:[.\/])*\z/)')
    end
  end
end
