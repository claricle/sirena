# frozen_string_literal: true

require "spec_helper"
require "yaml"

module PerformanceBenchmarkTruth
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
  UNATTRIBUTED_FIGURES = [
    "~200MB", "~100MB", "~30MB", "~2s (browser)", "~1s (JVM)", "<50ms"
  ].freeze
  EXPECTED_METADATA = {
    "layout" => "default",
    "title" => "Performance Benchmark",
    "permalink" => "/performance-benchmark/",
  }.freeze

  def self.metadata(source)
    match = source.match(/\A---\n(?<yaml>.*?)^---\n/m)
    match && YAML.safe_load(match[:yaml])
  end

  def self.report
    File.read(REPORT)
  end

  def self.missing_links
    PAGES.reject { |path| File.read(path).include?("performance-benchmark/") }
  end

  def self.stale_claims
    PAGES.product(STALE_CLAIMS).filter_map do |path, claim|
      File.basename(path) if File.read(path).match?(claim)
    end
  end

  def self.surviving_unattributed_figures
    pages = PAGES.map { |path| File.read(path) }.join("\n")
    UNATTRIBUTED_FIGURES.select { |figure| pages.include?(figure) }
  end
end

RSpec.describe PerformanceBenchmarkTruth do
  it "publishes the benchmark report at the route used by the docs" do
    expect(described_class.metadata(described_class.report))
      .to include(described_class::EXPECTED_METADATA)
  end

  it "dates the recorded benchmark run" do
    expect(described_class.report).to include("*Benchmark Date:* 2026-09-24")
  end

  it "documents both runnable benchmark tasks" do
    expect(described_class.report).to include(
      "bundle exec rake benchmark:compare",
      "bundle exec rake benchmark:quick"
    )
  end

  it "scopes the results to their measured evidence" do
    expect(described_class.report).to include(
      "single-machine measurements from one run",
      "Memory usage was not measured in this run"
    )
  end

  it "links every corrected user page to the scoped report" do
    expect(described_class.missing_links).to eq([])
  end

  it "removes claims that the report and runnable tasks do not exist" do
    expect(described_class.stale_claims).to eq([])
  end

  it "removes figures the recorded benchmark did not measure" do
    expect(described_class.surviving_unattributed_figures).to eq([])
  end
end
