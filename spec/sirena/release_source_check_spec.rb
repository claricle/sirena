# frozen_string_literal: true

require_relative "../../scripts/check_release_source"

# Concise builders for release-source examples.
module ReleaseSourceCheckSpecHelpers
  def successful_checks(sha)
    checks = Sirena::ReleaseSourceCheck::REQUIRED_CHECKS
    checks.each_with_index.map do |name, index|
      {
        "id" => index + 1,
        "name" => name,
        "head_sha" => sha,
        "status" => "completed",
        "conclusion" => "success",
      }
    end
  end

  def checked_main(check_runs: successful_checks(sha), source_sha: sha)
    described_class.checked_main_problems(
      source_sha: source_sha,
      main_sha: sha,
      check_runs: check_runs,
    )
  end

  def version_problems(changed_paths:, requested:, target_version: "0.2.0")
    described_class.version_change_problems(
      changed_paths: changed_paths,
      requested: requested,
      target_version: target_version,
      version_source: version_source,
    )
  end
end

RSpec.describe Sirena::ReleaseSourceCheck do
  include ReleaseSourceCheckSpecHelpers

  let(:sha) { "a" * 40 }

  describe ".checked_main_problems" do
    it "accepts the checked main head" do
      expect(checked_main).to eq([])
    end

    it "rejects a dispatch from a non-main commit" do
      expect(checked_main(source_sha: "b" * 40)).to include(/not main head/)
    end

    it "rejects a main head without both successful lane checks" do
      failed = successful_checks(sha).map(&:dup)
      failed.last["conclusion"] = "failure"

      problems = checked_main(check_runs: failed)
      expect(problems).to include(/no successful full-lane check/)
    end

    it "ignores a successful check belonging to another commit" do
      wrong_commit = successful_checks(sha).map do |check|
        check.merge("head_sha" => "b" * 40)
      end

      expect(checked_main(check_runs: wrong_commit)).to include(/no successful/)
    end

    it "does not let an older success hide the latest failed run" do
      stale_success = successful_checks(sha).first.merge("id" => 1)
      latest_failure = stale_success.merge("id" => 9, "conclusion" => "failure")
      checks = [stale_success, latest_failure, successful_checks(sha).last]

      problems = checked_main(check_runs: checks)
      expect(problems).to include(/no successful fast-lane check/)
    end
  end

  describe ".version_change_problems" do
    let(:version_source) { "module Sirena\n  VERSION = \"0.2.0\"\nend\n" }

    it "accepts an exact version-only bump" do
      paths = [described_class::VERSION_PATH]
      problems = version_problems(changed_paths: paths, requested: "minor")
      expect(problems).to eq([])
    end

    it "rejects any additional changed path" do
      paths = [described_class::VERSION_PATH, "README.adoc"]

      expect(version_problems(changed_paths: paths, requested: "0.2.0"))
        .to include(/README\.adoc/)
    end

    it "rejects a version file that does not contain the target" do
      paths = [described_class::VERSION_PATH]
      problems = version_problems(
        changed_paths: paths,
        requested: "patch",
        target_version: "0.2.1",
      )
      expect(problems)
        .to include(/expected "0\.2\.1"/)
    end

    it "accepts no commit when skip publishes the current version" do
      expect(version_problems(changed_paths: [], requested: "skip")).to eq([])
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
