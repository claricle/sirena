# frozen_string_literal: true

require_relative "../../scripts/ci_lane_timings"

RSpec.describe CiLaneTimings, :aggregate_failures do
  include CiJobFixtures

  describe ".slowest" do
    it "picks the longest runtime inside the lane and ignores other lanes" do
      jobs = [ci_job("lint", 1), ci_job("unit (ruby 3.4, ubuntu-latest)", 8),
              ci_job("pins", 0.1), ci_job("fresh-resolution", 20)]

      expect(described_class.slowest(jobs, "fast")["name"]).to eq("unit (ruby 3.4, ubuntu-latest)")
      expect(described_class.slowest(jobs, "full")["name"]).to eq("fresh-resolution")
    end

    it "measures started_at to completed_at, so queue time does not count" do
      queued = ci_job("unit (ruby 3.4, ubuntu-latest)", 5, queued: 30)
      busy = ci_job("lint", 6)

      expect(described_class.slowest([queued, busy], "fast")["name"]).to eq("lint")
      expect(described_class.duration(queued)).to eq(300)
    end

    it "skips jobs that did not run and reusable-workflow children belong to their lane" do
      jobs = [ci_job("docs-build / deploy", 9, conclusion: "skipped"),
              ci_job("links / link_checker", 2), ci_job("docs-build / build", 3)]

      expect(described_class.slowest(jobs, "full")["name"]).to eq("docs-build / build")
    end

    it "is nil when no job of the lane ran" do
      expect(described_class.sample([ci_job("lint", 1)], "full", {})).to be_nil
    end
  end

  describe ".classify_log" do
    {
      "an exact key hit" => ["Cache key: k\nCache hit for: k\nCache restored successfully", :warm],
      "a restore-key hit" => ["Cache key: k\nCache hit for restore-key: k-old", :restore_key],
      "a computed key and no hit line" => ["Cache key: k", :cold],
      "no cache line" => ["bundler-cache: false", nil],
    }.each do |label, (log, expected)|
      it "reads #{label}" do
        expect(described_class.classify_log(log)).to eq(expected)
      end
    end
  end

  describe ".median" do
    it "takes the middle of an odd count and the mean of the middle two of an even count" do
      expect(described_class.median([9, 1, 5])).to eq(5)
      expect(described_class.median([4, 1, 9, 2])).to eq(3.0)
    end
  end

  describe ".summarize" do
    it "splits by cache bucket with counts, median and max in minutes" do
      samples = [
        { cache: :warm, seconds: 360 }, { cache: :warm, seconds: 600 },
        { cache: :warm, seconds: 480 }, { cache: :restore_key, seconds: 720 },
        { cache: :restore_key, seconds: 840 }, { cache: :none, seconds: 60 }
      ]

      summary = described_class.summarize(samples)

      expect(summary[:warm]).to eq(count: 3, median: 8.0, max: 10.0)
      expect(summary[:restore_key]).to eq(count: 2, median: 13.0, max: 14.0)
      expect(summary[:cold]).to eq(count: 0, median: nil, max: nil)
      expect(summary[:none]).to eq(count: 1, median: 1.0, max: 1.0)
    end

    it "labels a sample with no cache line as none" do
      jobs = [ci_job("fresh-resolution", 7)]

      expect(described_class.sample(jobs, "full", {})).to include(cache: :none, seconds: 420)
      expect(described_class.sample(jobs, "full", "fresh-resolution" => :warm)).to include(cache: :warm)
    end
  end
end
