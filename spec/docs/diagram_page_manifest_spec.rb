# frozen_string_literal: true

require "spec_helper"
require "yaml"

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
  OUTPUTS = SLUGS.map do |slug|
    File.join("diagram_types", slug, "index.html")
  end.freeze
  MANIFEST = SLUGS.to_h do |slug|
    [File.join(SOURCE_DIR, "#{slug}.adoc"),
     File.join("diagram_types", slug, "index.html")]
  end.freeze
  CONFIG = YAML.safe_load_file(File.join(DOCS_DIR, "_config.yml")).freeze
end

RSpec.describe DiagramPageManifest do
  it "tracks every top-level non-generated diagram source" do
    sources = Dir[File.join(described_class::SOURCE_DIR, "*.adoc")]

    expect(described_class::MANIFEST.keys).to eq(sources)
  end

  it "configures every manifest source for its exact site path" do
    collection = described_class::CONFIG.dig("collections", "diagram_types")

    expect(collection).to eq(
      "output" => true,
      "permalink" => "/:collection/:path/",
    )
  end

  it "maps every manifest source onto that collection path" do
    expect(described_class::MANIFEST.values).to eq(described_class::OUTPUTS)
  end
end
