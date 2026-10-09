# frozen_string_literal: true

require "spec_helper"
require "yaml"

module LinksWorkflow
  ROOT = File.expand_path("../..", __dir__)
  CONFIG = File.join(ROOT, "docs/lychee.toml")
  SEED_DIR = File.join(ROOT, "docs/_lychee_seeds")
  WORKFLOW = File.join(ROOT, ".github/workflows/links.yml")

  SEEDS = {
    "broken-fragment.html" => "broken-fragment.html#missing-anchor",
    "broken-relative-link.html" => "./this-page-does-not-exist.html",
    "seeded-403.html" => "https://httpbin.org/status/403",
    "seeded-429.html" => "https://httpbin.org/status/429",
  }.freeze

  OUTCOMES = {
    "FRAGMENT_OUTCOME" => "${{ steps.seed_fragment.outcome }}",
    "RELATIVE_OUTCOME" => "${{ steps.seed_relative.outcome }}",
    "STATUS_403_OUTCOME" => "${{ steps.seed_403.outcome }}",
    "STATUS_429_OUTCOME" => "${{ steps.seed_429.outcome }}",
  }.freeze

  def self.workflow
    YAML.safe_load_file(WORKFLOW)
  end

  def self.steps
    workflow.fetch("jobs").fetch("link_checker").fetch("steps")
  end

  def self.step(name)
    steps.find { |candidate| candidate["name"] == name }
  end

  def self.config_facts
    config = File.read(CONFIG)
    [
      config.include?("accept = [200, 204, 301, 302, 307, 308, 503]"),
      config.include?("include_fragments = true"),
      !config.include?("check_anchors"),
      !config.include?("follow_redirects"),
    ]
  end

  def self.seed_targets
    SEEDS.to_h do |name, expected|
      source = File.read(File.join(SEED_DIR, name))
      [name, source.include?(%[href="#{expected}"])]
    end
  end

  def self.seed_steps
    steps.select { |candidate| candidate["id"]&.start_with?("seed_") }
  end

  def self.seed_failures_enabled?
    seed_steps.all? do |seed_step|
      seed_step["continue-on-error"] == true &&
        seed_step.dig("with", "fail") == true
    end
  end

  def self.status_proof?(status)
    pattern = "grep -Eq '(^|[^0-9])#{status}([^0-9]|$)' " \
              "link-seed-#{status}.md"
    step("Assert seeded failures")["run"].include?(pattern)
  end

  def self.ordinary_check_facts
    ordinary = step("Link Checker")
    [
      ordinary["continue-on-error"],
      ordinary.dig("with", "fail"),
      ordinary.dig("with", "args").include?("'docs/_site/**/*.html'"),
    ]
  end
end

RSpec.describe LinksWorkflow do
  it "rejects 403 and 429 while checking fragments and retaining 503" do
    expect(described_class.config_facts).to eq([true, true, true, true])
  end

  it "keeps four isolated fixtures with their intended broken targets" do
    expected = described_class::SEEDS.transform_values { true }

    expect(described_class.seed_targets).to eq(expected)
  end

  it "runs all four isolated seeds" do
    ids = described_class.seed_steps.map { |step| step["id"] }.sort

    expect(ids).to eq(%w[seed_403 seed_429 seed_fragment seed_relative])
  end

  it "configures every seed as an expected failure" do
    expect(described_class.seed_failures_enabled?).to be(true)
  end

  it "asserts every seeded outcome even after expected failures" do
    assertion = described_class.step("Assert seeded failures")
    facts = [assertion["if"], assertion["env"]]

    expect(facts).to eq(["always()", described_class::OUTCOMES])
  end

  %w[403 429].each do |status|
    it "proves the seeded #{status} response" do
      expect(described_class.status_proof?(status)).to be(true)
    end
  end

  it "still runs the ordinary built-site link check as a hard failure" do
    expect(described_class.ordinary_check_facts).to eq([nil, true, true])
  end
end
