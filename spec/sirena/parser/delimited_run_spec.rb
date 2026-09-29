# frozen_string_literal: true

require 'spec_helper'
require 'parslet'
require 'sirena/parser/atoms/delimited_run'

module DelimitedRunSpecHelpers
  def build_input(segment_count)
    "~#{Array.new(segment_count) { |i| "s#{i}" }.join('~')}~"
  end

  def min_call_time(attempts: 3, &block)
    Array.new(attempts) { average_call_time { cpu_time(&block) } }.min
  end

  def average_call_time
    total = 0.0
    calls = 0
    while total < 0.05
      total += yield
      calls += 1
      break if calls >= 2_000
    end
    total / calls
  end

  # Process.times, not clock_gettime: Windows Ruby has no CPU-time clock
  # for clock_gettime and raises Errno::EINVAL.
  def cpu_time
    start = Process.times
    yield
    finish = Process.times
    (finish.utime + finish.stime) - (start.utime + start.stime)
  end
end

RSpec.describe Sirena::Parser::Atoms::DelimitedRun do
  include DelimitedRunSpecHelpers

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

    # Crosses the 50_000-char chunk boundary `match_segment`'s adaptive
    # probe grows through -- a single segment longer than any probe size.
    it 'matches a single segment longer than the chunk ceiling' do
      long_run = 'a' * 120_000
      expect(atom.parse("~#{long_run}~").to_s).to eq("~#{long_run}~")
    end

    # Many short segments, crossing the boundary in TOTAL length: the bug
    # this atom exists to fix (a naive per-segment `GreedyRun` call pays
    # up to 50_000 chars of consume+rewind PER segment).
    it 'matches many short segments whose combined length crosses the chunk ceiling' do
      segments = Array.new(6_000) { |i| "s#{i}" }
      input = "~#{segments.join('~')}~"

      expect(atom.parse(input, prefix: true).to_s).to eq(input)
    end

    # Guards the O(n) fix: many short segments must parse in roughly
    # linear time, not the quadratic time a per-segment `GreedyRun` call
    # (chunk size bound to the WHOLE remaining source, not the segment)
    # produced -- measured at 1.8-8.9s per call before this fix, versus
    # under 0.05s after. An absolute bound would be too tight on a loaded
    # CI box; the scaling RATIO between a small and 8x-larger segment
    # count survives that (see spec/support/er_tilde_timing.rb's own
    # comment for the same reasoning applied to a sibling grammar rule).
    it 'scales linearly with the number of segments, not their square' do
      small_time = min_call_time { atom.parse(build_input(500), prefix: true) }
      large_time = min_call_time { atom.parse(build_input(4_000), prefix: true) }

      expect(large_time / small_time).to be < 30
    end
  end

  describe '#to_s_inner' do
    it 'renders the delimiter and segment pattern' do
      expect(atom.to_s).to eq('~(?:/\A(?:[^~\n])*/m~)+')
    end
  end
end
