# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

module ArchitectureMermaidBlocks
  ROOT = File.expand_path("../..", __dir__)
  ARCHITECTURE = File.join(ROOT, "ARCHITECTURE.md")
  OPENING_FENCE = /^```mermaid[ \t]*$/
  CLOSING_FENCE = /^```[ \t]*$/

  Block = Data.define(:line, :source)

  module_function

  def content
    File.read(ARCHITECTURE)
  end

  def opening_fence_count(source = content)
    source.scan(OPENING_FENCE).size
  end

  def blocks(source = content)
    extracted = []
    current = nil

    source.lines.each_with_index do |line, index|
      if current
        close_or_append(extracted, current, line)
        current = nil if line.match?(CLOSING_FENCE)
      elsif line.match?(OPENING_FENCE)
        current = Block.new(line: index + 1, source: +"")
      end
    end

    raise "unclosed Mermaid fence" if current

    extracted
  end

  def close_or_append(extracted, current, line)
    if line.match?(CLOSING_FENCE)
      extracted << current
    else
      current.source << line
    end
  end

  def section(title, level:)
    lines = content.lines
    heading = "#{"#" * level} #{title}"
    start = lines.index { |line| line.chomp == heading }
    raise "missing section: #{title}" unless start

    lines.drop(start + 1).take_while do |line|
      marks = line.match(/\A(?<marks>#+)[ \t]+/)&.[](:marks)
      !marks || marks.length > level
    end.join
  end

  def label(block)
    "ARCHITECTURE.md:#{block.line}"
  end
end

RSpec.describe ArchitectureMermaidBlocks do
  it "extracts every Mermaid opening fence" do
    facts = [
      described_class.opening_fence_count,
      described_class.blocks.size,
    ]

    expect(facts).to eq([3, 3])
  end

  it "keeps diagrams in the pipeline and registry sections" do
    sections = [
      described_class.section("Processing Pipeline", level: 2),
      described_class.section("Registry Pattern (Notation::Mermaid)", level: 3),
    ]

    expect(sections.map { |section| described_class.blocks(section).size })
      .to eq([1, 1])
  end

  described_class.blocks.each do |block|
    it "renders #{described_class.label(block)} as parseable SVG" do
      document = REXML::Document.new(Sirena.render(block.source))

      expect(document.root.name).to eq("svg")
    end
  end
end
