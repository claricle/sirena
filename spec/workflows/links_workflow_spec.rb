# frozen_string_literal: true

require "spec_helper"
require "socket"
require "yaml"
require_relative "../../scripts/lychee_seed_status_server"

module LinksWorkflow
  ROOT = File.expand_path("../..", __dir__)
  CONFIG = File.join(ROOT, "docs/lychee.toml")
  SEED_DIR = File.join(ROOT, "docs/_lychee_seeds")
  WORKFLOW = File.join(ROOT, ".github/workflows/links.yml")

  SEEDS = {
    "broken-fragment.html" => "broken-fragment.html#missing-anchor",
    "broken-relative-link.html" => "./this-page-does-not-exist.html",
    "seeded-403.html" => "http://127.0.0.1:49173/status/403",
    "seeded-429.html" => "http://127.0.0.1:49173/status/429",
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

  def self.status_server_step_facts
    start = step("Start seeded status server")
    stop = step("Stop seeded status server")
    [
      start["run"].include?("ruby scripts/lychee_seed_status_server.rb 49173"),
      start["run"].include?("http://127.0.0.1:49173/ready"),
      stop["if"],
      stop["run"].include?("lychee-seed-server.pid"),
    ]
  end

  def self.status_server_responses
    server = LycheeSeedStatusServer::Server.new(0)
    thread = Thread.new { server.run }
    %w[/ready /status/403 /status/429 /unknown].map do |path|
      status_response(server.port, path)
    end
  ensure
    server&.close
    thread&.join
  end

  def self.status_response(port, path)
    Socket.tcp("127.0.0.1", port) do |socket|
      socket.write("GET #{path} HTTP/1.1\r\nHost: localhost\r\n\r\n")
      socket.gets.split[1].to_i
    end
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

  it "starts and always stops the loopback status server" do
    expect(described_class.status_server_step_facts)
      .to eq([true, true, "always()", true])
  end

  it "serves exact local statuses for both HTTP failure classes" do
    expect(described_class.status_server_responses).to eq([204, 403, 429, 404])
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
