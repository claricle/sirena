# frozen_string_literal: true

require_relative "../../scripts/check_changelog"

RSpec.describe Sirena::ChangelogCheck do
  let(:good) do
    [
      "## [Unreleased]", "", "## [0.2.0] - 2026-10-01", "",
      "### Fixed", "- a thing", "", "## [0.1.0]", ""
    ].join("\n")
  end

  describe ".target_version" do
    {
      ["skip", "0.1.9"] => "0.1.9",
      ["patch", "0.1.9"] => "0.1.10",
      ["minor", "0.1.9"] => "0.2.0",
      ["major", "0.1.9"] => "1.0.0",
      ["0.4.2", "0.1.9"] => "0.4.2"
    }.each do |(input, current), expected|
      it "maps #{input} from #{current} to #{expected}" do
        expect(described_class.target_version(input, current)).to eq(expected)
      end
    end

    it "refuses pre-release keywords" do
      expect { described_class.target_version("rc", "0.1.0") }.to raise_error(ArgumentError, /rc/)
    end
  end

  describe ".problems" do
    it "accepts a dated section with a categorised bullet" do
      expect(described_class.problems(good, "0.2.0")).to eq([])
    end

    it "blocks a version with no section" do
      expect(described_class.problems(good, "0.3.0")).to eq(["no `## [0.3.0] - YYYY-MM-DD` section in the changelog"])
    end

    it "blocks an empty Unreleased section, the seeded no-entry release" do
      expect(described_class.problems(good, "Unreleased")).to include(/no bullet/)
    end

    it "blocks a section with a bullet outside any category" do
      text = "## [0.2.0] - 2026-10-01\n\n- loose bullet\n"
      expect(described_class.problems(text, "0.2.0")).to include(/no bullet/)
    end

    it "does not count an empty bullet" do
      text = "## [0.2.0] - 2026-10-01\n\n### Fixed\n- \n"
      expect(described_class.problems(text, "0.2.0")).to include(/no bullet/)
    end

    it "does not count a bullet from the next section" do
      text = "## [0.2.0] - 2026-10-01\n\n### Fixed\n\n## [0.1.0] - 2026-09-01\n\n### Fixed\n- old\n"
      expect(described_class.problems(text, "0.2.0")).to include(/no bullet/)
    end

    it "blocks an undated section" do
      text = "## [0.2.0]\n\n### Fixed\n- a\n"
      expect(described_class.problems(text, "0.2.0")).to include(/no date/)
    end
  end

  describe "command line" do
    include ChangelogScriptHelper

    it "exits 0 when releasable" do
      _out, _err, status = run_script("0.2.0", changelog: good)
      expect(status.exitstatus).to eq(0)
    end

    it "exits 1 when no releasable entry exists" do
      _out, err, status = run_script("patch", changelog: good)
      expect([status.exitstatus, err]).to match([1, /0\.1\.10/])
    end
  end
end
