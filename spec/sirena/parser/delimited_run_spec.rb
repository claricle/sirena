# frozen_string_literal: true

require 'spec_helper'
require 'parslet'
require 'sirena/parser/atoms/delimited_run'

module DelimitedRunSpecHelpers
  def build_input(segment_count)
    "~#{Array.new(segment_count) { |i| "s#{i}" }.join('~')}~"
  end
end

RSpec.describe Sirena::Parser::Atoms::DelimitedRun do
  include DelimitedRunSpecHelpers
  include CpuTiming

  let(:atom) { described_class.new('~', '[^~\n]') }

  describe '#initialize' do
    it 'rejects a multi-character delimiter' do
      expect { described_class.new('~~', '[^~\n]') }
        .to raise_error(ArgumentError, /one character/)
    end
  end

  describe '#try' do
    it 'matches a single delimited segment' do
      expect(atom.parse('~foo~').to_s).to eq('~foo~')
    end

    it 'matches through the last delimiter, not the first' do
      expect(atom.parse('~bar~baz qux~', prefix: true).to_s).to eq('~bar~baz qux~')
    end

    it 'matches an empty segment between two adjacent delimiters' do
      expect(atom.parse('~~').to_s).to eq('~~')
    end

    it 'fails when there is no opening delimiter' do
      expect { atom.parse('foo~bar~') }.to raise_error(Parslet::ParseFailed)
    end

    it 'fails when the opening delimiter is never closed' do
      expect { atom.parse('~foo') }.to raise_error(Parslet::ParseFailed)
    end

    it 'stops the segment run at a character outside its class, refusing to cross it' do
      expect { atom.parse("~foo\nbar~") }.to raise_error(Parslet::ParseFailed)
    end

    it 'leaves trailing unmatched input for the next atom' do
      expect(atom.parse('~foo~ rest', prefix: true).to_s).to eq('~foo~')
    end

    # A single segment longer than the largest probe chunk (50_000), so
    # `GreedyRun.scan` needs several doubling rounds to read it.
    it 'matches a single segment longer than the chunk ceiling' do
      long_run = 'a' * 120_000
      expect(atom.parse("~#{long_run}~").to_s).to eq("~#{long_run}~")
    end

    # Many short segments, each closed by its own delimiter: every segment
    # is a fresh `GreedyRun.scan`, so the source position must carry
    # correctly from one segment to the next.
    it 'matches many short segments, each closed by its own delimiter' do
      segments = Array.new(6_000) { |i| "s#{i}" }
      input = "~#{segments.join('~')}~"

      expect(atom.parse(input, prefix: true).to_s).to eq(input)
    end

    # Guards linear time: every segment's scan must start from the small
    # initial probe. A scan sized to the WHOLE remaining source instead
    # would cost O(remaining) per segment, so total time grows with the
    # square of the segment count. An absolute bound would be too tight on
    # a loaded CI box; the scaling RATIO between a small and 8x-larger
    # segment count survives that (see spec/support/cpu_timing.rb's header
    # comment).
    it 'scales linearly with the number of segments, not their square' do
      small_time = min_call_time { cpu_time { atom.parse(build_input(500), prefix: true) } }
      large_time = min_call_time { cpu_time { atom.parse(build_input(4_000), prefix: true) } }

      expect(large_time / small_time).to be < 30
    end
  end

  describe '#to_s_inner' do
    it 'renders the delimiter and segment pattern' do
      expect(atom.to_s).to eq('~(?:/\A(?:[^~\n])*/m~)+')
    end
  end
end
