# frozen_string_literal: true

require "yaml"
require_relative "../../scripts/check_workflow_pins"

RSpec.describe WorkflowPins do
  let(:jobs) { YAML.safe_load_file(".github/workflows/ci.yml").fetch("jobs") }
  let(:guard) { jobs.fetch("scoreboard-baseline") }
  let(:steps) { guard.fetch("steps") }

  %w[fast-lane full-lane].each do |lane|
    it "requires the committed baseline guard in #{lane}" do
      expect(jobs.fetch(lane).fetch("needs")).to include("scoreboard-baseline")
    end
  end

  it "fetches complete ancestry for every event" do
    expect(steps.first.dig("with", "fetch-depth")).to eq(0)
  end

  it "fetches the explicit PR or merge-group base ref" do
    expected = "${{ github.event.pull_request.base.ref || " \
               "github.event.merge_group.base_ref || '' }}"
    expect(steps.find { |step| step["name"] == "Fetch the event base branch" }
      .dig("env", "BASE_REF")).to eq(expected)
  end

  it "executes the actual read-only event-aware guard" do
    expect(steps.last.fetch("run"))
      .to eq("bundle exec ruby scripts/scoreboard_baseline.rb")
  end

  context "with repeatable cache proof" do
    let(:cache_version) do
      "${{ inputs.cache_version && inputs.cache_version != '0' && " \
        "format('{0}-{1}', inputs.cache_version, github.job) || '0' }}"
    end
    let(:cached_steps) do
      steps = jobs.values.flat_map { |job| job.fetch("steps", []) }
      steps.select { |step| step.dig("with", "bundler-cache") }
    end

    it "keeps default caches and separates cold-proof job namespaces" do
      expect(cached_steps.map { |step| step.dig("with", "cache-version") }.uniq)
        .to eq([cache_version])
    end
  end
end
