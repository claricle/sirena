# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::ErrorReport do
  describe '.cause_diagnostics' do
    it 'is empty for an error with no cause' do
      expect(described_class.cause_diagnostics(RuntimeError.new('lonely'))).to eq('')
    end

    it 'names the cause class and message the wrapper dropped' do
      error = begin
        begin
          raise ArgumentError, 'the real fault'
        rescue ArgumentError
          raise 'Rendering failed: the real fault'
        end
      rescue RuntimeError => e
        e
      end

      report = described_class.cause_diagnostics(error)

      expect(report).to include('Caused by: ArgumentError: the real fault')
    end

    it 'reports every cause in the chain, nearest first' do
      error = begin
        begin
          begin
            raise ArgumentError, 'innermost'
          rescue ArgumentError
            raise TypeError, 'middle'
          end
        rescue TypeError
          raise 'outermost'
        end
      rescue RuntimeError => e
        e
      end

      report = described_class.cause_diagnostics(error)

      expect(report.scan(/^Caused by: (\w+)/).flatten).to eq(%w[TypeError ArgumentError])
    end

    it 'survives a cause whose backtrace is nil' do
      cause = ArgumentError.new('never raised, so never given a backtrace')
      error = RuntimeError.new('wrapper')
      allow(error).to receive(:cause).and_return(cause)

      expect(described_class.cause_diagnostics(error))
        .to eq('Caused by: ArgumentError: never raised, so never given a backtrace')
    end

    # The exhaustion path is the one this module exists for, and it is
    # exactly where a trace runs to six figures of frames. An uncapped
    # report would make `--verbose` useless on the failure that needed it.
    it 'caps a long cause backtrace and says how many frames it dropped' do
      cause = ArgumentError.new('deep')
      cause.set_backtrace(Array.new(Sirena::ErrorReport::CAUSE_FRAME_LIMIT + 7) { |i| "frame_#{i}" })
      error = RuntimeError.new('wrapper')
      allow(error).to receive(:cause).and_return(cause)

      report = described_class.cause_diagnostics(error)

      expect(report).to include('frame_0')
      expect(report).not_to include("frame_#{Sirena::ErrorReport::CAUSE_FRAME_LIMIT}")
      expect(report).to end_with('... 7 more frames')
    end
  end
end
