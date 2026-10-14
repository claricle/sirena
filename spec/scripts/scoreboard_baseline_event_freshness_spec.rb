# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../../scripts/scoreboard_baseline"

# These are real local Git histories and Ruby/Rake processes. They do not
# establish hosted GitHub event fetching or pinned oracle verdict evidence.
RSpec.describe ScoreboardBaseline, :aggregate_failures do
  let(:root) { Dir.mktmpdir("scoreboard-event-freshness") }
  let(:repo) { SeededFreshnessRepo.new(root, mode: mode, scenario: scenario) }
  let(:checks) { repo.checks }

  after { FileUtils.remove_entry(root) }

  SeededFreshnessRepo::MODES.each do |event_mode|
    context "with a simulated #{event_mode} event" do
      let(:mode) { event_mode }

      context "when the recorded corpus matches real rendering" do
        let(:scenario) { :unchanged }

        it "accepts both commands with the resolved baseline and mode" do
          expect(checks.statuses).to eq([0, 0])
          expect(checks.baseline.json.values_at("baseline", "mode"))
            .to eq([repo.expected_baseline, repo.baseline_mode])
          expect(checks.baseline.json.fetch("errors")).to eq([])
          expect(checks.freshness.out).to include("clean (2 cases")
        end
      end

      context "when an improvement is recorded after real rendering" do
        let(:scenario) { :recorded_improvement }

        it "accepts the improvement through both commands" do
          expect(checks.statuses).to eq([0, 0])
          expect(checks.freshness.out).to include("clean (2 cases")
        end
      end

      context "when the source regresses" do
        let(:scenario) { :regression }

        it "identifies a declared Git regression or consistency drift" do
          expected = repo.consistency_only? ? [0, 1] : [1, 0]
          expect(checks.statuses).to eq(expected)
          expect(checks.failure).to include("pie/target.mmd")
            .and match(/regressed/i)
        end
      end

      context "when a corpus case is deleted" do
        let(:scenario) { :deletion }

        it "identifies deletion from Git or the fresh case set" do
          expected = repo.consistency_only? ? [0, 1] : [1, 0]
          message = repo.consistency_only? ? "REGRESSED" : "deleted case"
          expect(checks.statuses).to eq(expected)
          expect(checks.failure).to include(message, "pie/target.mmd")
        end
      end

      context "when an actual improvement has not been recorded" do
        let(:scenario) { :stale_improvement }

        it "passes Git validation and fails the real fresh measurement" do
          expect(checks.statuses).to eq([0, 1])
          expect(checks.freshness.out)
            .to include("IMPROVED BUT NOT RECORDED", "pie/target.mmd")
        end
      end
    end
  end
end
