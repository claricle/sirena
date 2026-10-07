# frozen_string_literal: true

RSpec.describe SpeedClock do
  include SpeedRetrySandbox

  refusal = "tag this example :speed: it reads the clock " \
            "(spec/support/speed_retry.rb)"

  { cpu_time: CpuTiming, wall_time: described_class }.each do |clock, helpers|
    {
      "lets a :speed example read #{clock}" => [[:speed], nil],
      "refuses #{clock} to an example not tagged :speed" => [[], refusal],
    }.each do |behaviour, (tags, failure)|
      it behaviour do
        outcome = run_clock_read(tags, helpers, clock)
        expect(outcome.failure).to eq(failure)
      end
    end
  end

  describe "the spec files" do
    # Only the two files that implement the clocks may read it directly.
    let(:clock_sources) do
      ["speed_clock.rb", "cpu_timing.rb"].map do |name|
        File.join(__dir__, "support", name)
      end
    end
    let(:files) { Dir[File.join(__dir__, "**", "*.rb")] - clock_sources }
    let(:helpers) { Dir[File.join(__dir__, "support", "*.rb")] - clock_sources }

    it "include the timed benchmark this check is for" do
      benchmark = "spec/benchmarks/flowchart_subgraph_benchmark.rb"
      expect(files).to include(a_string_ending_with(benchmark))
    end

    # Keep this: it fails if `files` stops scanning spec/support again.
    it "include every support helper but the clocks themselves" do
      expect(files).to include(*helpers)
    end

    it "read the clock only through wall_time or cpu_time" do
      offenders = files.flat_map { |path| RawClockReads.find(path) }
      expect(offenders).to be_empty
    end
  end
end
