# frozen_string_literal: true

require "spec_helper"
require "timeout"

RSpec.describe Sirena::ErrorReport do
  let(:nil_backtrace_diagnostic) do
    "Caused by: ArgumentError: never raised, so never given a backtrace"
  end
  let(:cyclic_error_chain) do
    outer = RuntimeError.new("outer")
    middle = TypeError.new("middle")
    inner = ArgumentError.new("inner")
    allow(outer).to receive(:cause).and_return(middle)
    allow(middle).to receive(:cause).and_return(inner)
    allow(inner).to receive(:cause).and_return(middle)
    outer
  end

  describe ".cause_diagnostics" do
    let(:nested_error_chain) do
      begin
        begin
          raise ArgumentError, "innermost"
        rescue ArgumentError
          raise TypeError, "middle"
        end
      rescue TypeError
        raise "outermost"
      end
    rescue RuntimeError => e
      e
    end
    let(:wrapped_argument_error) do
      begin
        raise ArgumentError, "the real fault"
      rescue ArgumentError
        raise "Rendering failed: the real fault"
      end
    rescue RuntimeError => e
      e
    end

    it "is empty for an error with no cause" do
      expect(described_class.cause_diagnostics(RuntimeError.new("lonely")))
        .to eq("")
    end

    it "names the cause class and message the wrapper dropped" do
      report = described_class.cause_diagnostics(wrapped_argument_error)
      expect(report).to include("Caused by: ArgumentError: the real fault")
    end

    it "reports every cause in the chain, nearest first" do
      report = described_class.cause_diagnostics(nested_error_chain)
      expect(report.scan(/^Caused by: (\w+)/).flatten)
        .to eq(%w[TypeError ArgumentError])
    end

    it "stops when an error names itself as its cause" do
      error = RuntimeError.new("self-referential")
      allow(error).to receive(:cause).and_return(error)

      report = Timeout.timeout(1) { described_class.cause_diagnostics(error) }

      expect(report).to eq("")
    end

    it "reports each cause once when the chain contains a cycle" do
      diagnostics = described_class.method(:cause_diagnostics)
      report = Timeout.timeout(1) { diagnostics.call(cyclic_error_chain) }

      expect(report.scan(/^Caused by: (.+)$/).flatten)
        .to eq(["TypeError: middle", "ArgumentError: inner"])
    end

    it "survives a cause whose backtrace is nil" do
      cause = ArgumentError.new("never raised, so never given a backtrace")
      error = RuntimeError.new("wrapper")
      allow(error).to receive(:cause).and_return(cause)

      diagnostics = described_class.cause_diagnostics(error)
      expect(diagnostics).to eq(nil_backtrace_diagnostic)
    end

    # The exhaustion path is the one this module exists for, and it is
    # exactly where a trace runs to six figures of frames. An uncapped
    # report would make `--verbose` useless on the failure that needed it.
    describe "a cause backtrace beyond the frame limit" do
      let(:report) do
        cause = ArgumentError.new("deep")
        frames = Array.new(described_class::CAUSE_FRAME_LIMIT + 7) do |index|
          "frame_#{index}"
        end
        cause.set_backtrace(frames)
        error = RuntimeError.new("wrapper")
        allow(error).to receive(:cause).and_return(cause)
        described_class.cause_diagnostics(error)
      end

      it "keeps the first frame" do
        expect(report).to include("frame_0")
      end

      it "omits the frame immediately beyond the cap" do
        expect(report)
          .not_to include("frame_#{described_class::CAUSE_FRAME_LIMIT}")
      end

      it "reports the exact number of dropped frames" do
        expect(report).to end_with("... 7 more frames")
      end
    end
  end
end
