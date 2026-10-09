# frozen_string_literal: true

require "spec_helper"
require "yaml"

module PerformanceBenchmarkTruthSpec
  ROOT = File.expand_path("../..", __dir__)
  REPORT = File.join(ROOT, "docs/PERFORMANCE_BENCHMARK.adoc")
  PAGES = %w[
    docs/index.adoc
    docs/_features/index.adoc
    docs/_pages/comparison.adoc
    docs/_pages/compatibility.adoc
  ].map { |path| File.join(ROOT, path) }.freeze

  STALE_CLAIMS = [
    /No committed, reproducible benchmark/i,
    /No committed benchmark yet/i,
    /No recorded benchmark yet/i,
    /tasks .* do not currently run/i,
  ].freeze

  def self.metadata(source)
    match = source.match(/\A---\n(?<yaml>.*?)^---\n/m)
    match && YAML.safe_load(match[:yaml])
  end
end

RSpec.describe PerformanceBenchmarkTruthSpec do
  it "publishes the dated benchmark report at the route used by the docs" do
    report = File.read(described_class::REPORT)

    expect(described_class.metadata(report)).to include(
      "layout" => "default",
      "title" => "Performance Benchmark",
      "permalink" => "/performance-benchmark/",
    )
    expect(report).to include("*Benchmark Date:* 2026-09-24")
    expect(report).to include("bundle exec rake benchmark:compare")
    expect(report).to include("bundle exec rake benchmark:quick")
    expect(report).to include("single-machine measurements from one run")
    expect(report).to include("Memory usage was not measured in this run")
  end

  it "links every corrected user page to the scoped report" do
    missing_links = described_class::PAGES.reject do |path|
      File.read(path).include?("performance-benchmark/")
    end

    expect(missing_links).to eq([])
  end

  it "removes the obsolete claims that the report and runnable tasks do not exist" do
    stale = described_class::PAGES.product(described_class::STALE_CLAIMS).filter_map do |path, claim|
      File.basename(path) if File.read(path).match?(claim)
    end

    expect(stale).to eq([])
  end
end
