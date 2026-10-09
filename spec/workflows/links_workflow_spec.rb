# frozen_string_literal: true

require "spec_helper"
require "yaml"

module LinksWorkflowSpec
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
end

RSpec.describe LinksWorkflowSpec do
  it "rejects 403 and 429 while checking fragments and retaining 503" do
    config = File.read(described_class::CONFIG)
    facts = [
      config.include?("accept = [200, 204, 301, 302, 307, 308, 503]"),
      config.include?("include_fragments = true"),
      !config.include?("check_anchors"),
      !config.include?("follow_redirects"),
    ]

    expect(facts).to eq([true, true, true, true])
  end

  it "keeps four isolated fixtures with their intended broken targets" do
    targets = described_class::SEEDS.to_h do |name, expected|
      source = File.read(File.join(described_class::SEED_DIR, name))
      [name, source.include?(%[href="#{expected}"])]
    end

    expect(targets).to eq(described_class::SEEDS.transform_values { true })
  end

  it "runs every seed as an expected failure and asserts its outcome" do
    seed_steps = described_class.steps.select { |step| step["id"]&.start_with?("seed_") }
    assertion = described_class.step("Assert seeded failures")
    all_fail = seed_steps.all? do |step|
      step["continue-on-error"] == true && step.dig("with", "fail") == true
    end
    status_proofs = %w[403 429].all? do |status|
      assertion["run"].include?("grep -Eq '(^|[^0-9])#{status}([^0-9]|$)' link-seed-#{status}.md")
    end
    facts = [
      seed_steps.map { |step| step["id"] }.sort,
      all_fail,
      assertion["if"],
      assertion["env"],
      status_proofs,
    ]

    expect(facts).to eq([
      %w[seed_403 seed_429 seed_fragment seed_relative],
      true,
      "always()",
      described_class::OUTCOMES,
      true,
    ])
  end

  it "still runs the ordinary built-site link check as a hard failure" do
    ordinary = described_class.step("Link Checker")
    facts = [
      ordinary["continue-on-error"],
      ordinary.dig("with", "fail"),
      ordinary.dig("with", "args").include?("'docs/_site/**/*.html'"),
    ]

    expect(facts).to eq([nil, true, true])
  end
end
