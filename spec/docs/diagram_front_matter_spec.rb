# frozen_string_literal: true

require "spec_helper"
require "yaml"

module DiagramFrontMatterSpec
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
end

RSpec.describe DiagramFrontMatterSpec do
  it "publishes every top-level diagram page with accurate front matter" do
    failures = described_class::PAGES.filter_map do |path|
      source = File.read(path)
      metadata = described_class.metadata(source)
      title = metadata&.fetch("title", "").to_s.strip
      fields_match = described_class::EXPECTED.all? do |key, value|
        metadata&.fetch(key, nil) == value
      end
      next if fields_match && title.casecmp?(described_class.title(source))

      File.basename(path)
    end

    expect(failures).to eq([])
  end
end
