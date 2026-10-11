# frozen_string_literal: true

require "spec_helper"
require "bundler"
require "fileutils"
require "open3"
require "tmpdir"

module DiagramPageManifest
  ROOT = File.expand_path("../..", __dir__)
  DOCS_DIR = File.join(ROOT, "docs")
  SOURCE_DIR = File.join(DOCS_DIR, "_diagram_types")
  SLUGS = %w[
    architecture-diagram block-diagram c4-diagram class-diagram er-diagram
    error-diagram flowchart gantt-chart git-graph index info-diagram
    kanban-diagram mindmap packet-diagram pie-chart quadrant-chart radar-chart
    requirement-diagram sankey-diagram sequence-diagram state-diagram timeline
    treemap-diagram user-journey xy-chart
  ].freeze
  MANIFEST = SLUGS.to_h do |slug|
    [File.join(SOURCE_DIR, "#{slug}.adoc"),
     File.join("diagram_types", slug, "index.html")]
  end.freeze
  BUILD_ENV = {
    "BUNDLE_GEMFILE" => File.join(DOCS_DIR, "Gemfile"),
    "JEKYLL_ENV" => "production",
  }.freeze
end

RSpec.describe DiagramPageManifest do
  let(:site_dir) { Dir.mktmpdir("sirena-diagram-pages") }
  let(:build_result) do
    Bundler.with_unbundled_env do
      Open3.capture3(
        described_class::BUILD_ENV,
        "bundle", "exec", "jekyll", "build",
        "--source", described_class::DOCS_DIR,
        "--destination", site_dir, "--quiet"
      )
    end
  end

  after do
    FileUtils.rm_rf(site_dir)
  end

  it "tracks every top-level non-generated diagram source" do
    sources = Dir[File.join(described_class::SOURCE_DIR, "*.adoc")]

    expect(described_class::MANIFEST.keys).to eq(sources)
  end

  it "publishes every manifest source to its exact site path" do
    _, stderr, status = build_result
    missing = described_class::MANIFEST.values.reject do |output|
      File.file?(File.join(site_dir, output))
    end
    diagnostic = status.success? ? "missing outputs: #{missing.join(', ')}" : stderr

    expect([status.success?, missing]).to eq([true, []]), diagnostic
  end
end
