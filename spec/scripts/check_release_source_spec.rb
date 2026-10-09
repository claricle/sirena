# frozen_string_literal: true

require_relative "../../scripts/check_release_source"

RSpec.describe Sirena::ReleaseSourceCheck do
  let(:sha) { "a" * 40 }
  let(:successful_checks) do
    described_class::REQUIRED_CHECKS.each_with_index.map do |name, index|
      { "id" => index + 1, "name" => name, "head_sha" => sha,
        "status" => "completed", "conclusion" => "success" }
    end
  end

  describe ".checked_main_problems" do
    it "accepts the checked main head" do
      problems = described_class.checked_main_problems(
        source_sha: sha, main_sha: sha, check_runs: successful_checks
      )

      expect(problems).to eq([])
    end

    it "rejects a dispatch from a non-main commit" do
      problems = described_class.checked_main_problems(
        source_sha: "b" * 40, main_sha: sha, check_runs: successful_checks
      )

      expect(problems).to include(/not main head/)
    end

    it "rejects a main head without both successful lane checks" do
      failed = successful_checks.map(&:dup)
      failed.last["conclusion"] = "failure"
      problems = described_class.checked_main_problems(
        source_sha: sha, main_sha: sha, check_runs: failed
      )

      expect(problems).to include(/no successful full-lane check/)
    end

    it "ignores a successful check belonging to another commit" do
      wrong_commit = successful_checks.map { |check| check.merge("head_sha" => "b" * 40) }
      problems = described_class.checked_main_problems(
        source_sha: sha, main_sha: sha, check_runs: wrong_commit
      )

      expect(problems).to include(/no successful fast-lane check/, /no successful full-lane check/)
    end

    it "does not let an older success hide the latest failed run" do
      stale_success = successful_checks.first.merge("id" => 1)
      latest_failure = stale_success.merge("id" => 9, "conclusion" => "failure")
      problems = described_class.checked_main_problems(
        source_sha: sha, main_sha: sha,
        check_runs: [stale_success, latest_failure, successful_checks.last]
      )

      expect(problems).to include(/no successful fast-lane check/)
    end
  end

  describe ".version_change_problems" do
    let(:version_source) { "module Sirena\n  VERSION = \"0.2.0\"\nend\n" }

    it "accepts an exact version-only bump" do
      problems = described_class.version_change_problems(
        changed_paths: [described_class::VERSION_PATH], requested: "minor",
        target_version: "0.2.0", version_source: version_source
      )

      expect(problems).to eq([])
    end

    it "rejects any additional changed path" do
      problems = described_class.version_change_problems(
        changed_paths: [described_class::VERSION_PATH, "README.adoc"], requested: "0.2.0",
        target_version: "0.2.0", version_source: version_source
      )

      expect(problems).to include(/README\.adoc/)
    end

    it "rejects a version file that does not contain the target" do
      problems = described_class.version_change_problems(
        changed_paths: [described_class::VERSION_PATH], requested: "patch",
        target_version: "0.2.1", version_source: version_source
      )

      expect(problems).to include(/expected \"0\.2\.1\"/)
    end

    it "accepts no commit when skip publishes the current version" do
      problems = described_class.version_change_problems(
        changed_paths: [], requested: "skip", target_version: "0.2.0", version_source: version_source
      )

      expect(problems).to eq([])
    end
  end

  describe ".replace_version" do
    it "replaces the sole version assignment and preserves the file" do
      source = "module Sirena\n  VERSION = \"0.1.0\"\nend\n"

      expect(described_class.replace_version(source, "0.2.0"))
        .to eq("module Sirena\n  VERSION = \"0.2.0\"\nend\n")
    end

    it "rejects a missing or ambiguous assignment" do
      expect { described_class.replace_version("", "0.2.0") }
        .to raise_error(ArgumentError, /exactly one/)
    end
  end
end
