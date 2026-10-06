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
    let(:files) do
      support = File.join(__dir__, "support", "")
      Dir[File.join(__dir__, "**", "*.rb")]
        .reject { |path| path.start_with?(support) || path == __FILE__ }
    end

    it "include the timed ones this check is for" do
      benchmark = "spec/benchmarks/flowchart_subgraph_benchmark.rb"
      expect(files).to include(a_string_ending_with(benchmark))
    end

    it "read the clock only through wall_time or cpu_time" do
      raw_clock = /Process\.(?:clock_gettime|times)
                  |Benchmark\.(?:realtime|measure|bm)/x
      offenders = files.select { |path| File.read(path).match?(raw_clock) }
      expect(offenders).to be_empty
    end
  end
end
