# frozen_string_literal: true

require "spec_helper"
require_relative "../../scripts/plantuml_scoreboard"

RSpec.describe PlantumlScoreboard do
  let(:row) do
    { "notation" => "plantuml", "type" => "class",
      "provenance" => "upstream-fixture" }
      .merge(described_class.summarize(37, 35, 31))
  end

  describe ".summarize" do
    it "derives the rate and status from the counts" do
      expect(row).to include(
        "passing" => 31, "pass_rate" => 0.8857,
        "status" => "31/35 oracle-valid cases pass; " \
                    "2/37 cases are rejected by the pinned oracle"
      )
    end

    it "reports a zero rate, not NaN, when no case is oracle-valid" do
      expect(described_class.summarize(2, 0, 0)).to include("pass_rate" => 0.0)
    end
  end

  describe ".drift" do
    it "is empty when every measured field matches" do
      expect(described_class.drift([row], [row.dup])).to be_empty
    end

    it "names the type and field of a passing count that moved" do
      fresh = row.merge(described_class.summarize(37, 35, 32))

      expect(described_class.drift([row], [fresh]).join("\n"))
        .to include("class.passing: committed 31, measured 32")
    end
  end

  describe ".check!" do
    before do
      allow(described_class).to receive(:load_scoreboard).and_return([row])
    end

    it "aborts when the fresh measurement differs from the committed file" do
      drifted = row.merge(described_class.summarize(37, 35, 0))
      allow(described_class).to receive(:fresh_rows).and_return([drifted])

      expect { described_class.check! }
        .to raise_error(SystemExit).and output(/class.passing/).to_stdout
    end

    it "returns quietly when the measurement matches" do
      allow(described_class).to receive(:fresh_rows).and_return([row])

      expect { described_class.check! }.to output(/clean/).to_stdout
    end
  end
end
