# frozen_string_literal: true

require "spec_helper"
require "yaml"

module DiagramFrontMatter
  ROOT = File.expand_path("../..", __dir__)
  PAGE_DIR = File.join(ROOT, "docs/_diagram_types")
  PAGES = Dir[File.join(PAGE_DIR, "*.adoc")]
    .reject { |path| File.basename(path) == "index.adoc" }
    .sort
    .freeze

  EXPECTED = {
    "layout" => "default",
    "parent" => "Diagram Types",
  }.freeze

  def self.metadata(source)
    match = source.match(/\A---\n(?<yaml>.*?)^---\n/m)
    match && YAML.safe_load(match[:yaml])
  end

  def self.title(source)
    heading = source.each_line.find { |line| line.match?(/\A={1,2} /) }
    heading.sub(/\A={1,2} /, "").strip
  end

  def self.failures
    PAGES.filter_map do |path|
      source = File.read(path)
      page_metadata = metadata(source)
      page_title = page_metadata&.fetch("title", "").to_s.strip
      fields_match = EXPECTED.all? do |key, value|
        page_metadata&.fetch(key, nil) == value
      end
      next if fields_match && page_title.casecmp?(title(source))

      File.basename(path)
    end
  end
end

RSpec.describe DiagramFrontMatter do
  it "publishes every top-level diagram page with accurate front matter" do
    expect(described_class.failures).to eq([])
  end
end
