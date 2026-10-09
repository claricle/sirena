# frozen_string_literal: true

require "spec_helper"

module AsciidocLinkSyntax
  ROOT = File.expand_path("../..", __dir__)
  EXPECTED_SOURCE_LINK_COUNTS = {
    "architecture-diagram.adoc" => 6,
    "c4-diagram.adoc" => 9,
    "pie-chart.adoc" => 8,
    "quadrant-chart.adoc" => 16,
  }.freeze
  PAGES = EXPECTED_SOURCE_LINK_COUNTS.keys.to_h do |name|
    [name, File.join(ROOT, "docs/_diagram_types", name)]
  end.freeze
  MARKDOWN_SOURCE_LINK = %r{\[[^\]]+\]\((?:\.\./)?(?:lib|spec)/[^)]+\)}
  SOURCE_URL = Regexp.new(
    "https://github\\.com/claricle/sirena/blob/main/" \
    "(?:lib|spec)/[^\\s\\[]+\\[[^\\]]+\\]",
  )

  def self.markdown_source_links
    PAGES.values.flat_map { |path| File.read(path).scan(MARKDOWN_SOURCE_LINK) }
  end

  def self.source_link_counts
    PAGES.transform_values { |path| File.read(path).scan(SOURCE_URL).size }
  end
end

RSpec.describe AsciidocLinkSyntax do
  it "uses AsciiDoc syntax for source links in the affected pages" do
    expect(described_class.markdown_source_links).to eq([])
  end

  it "preserves every source link as a GitHub repository URL" do
    expect(described_class.source_link_counts)
      .to eq(described_class::EXPECTED_SOURCE_LINK_COUNTS)
  end
end
