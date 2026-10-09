# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

module ArchitectureMermaidBlocks
  ROOT = File.expand_path("../..", __dir__)
  ARCHITECTURE = File.join(ROOT, "ARCHITECTURE.md")
  OPENING_FENCE = /^```mermaid[ \t]*$/
  CLOSING_FENCE = /^```[ \t]*$/

  Block = Data.define(:line, :source)

  class Extractor
    def initialize(source)
      @source = source
      @blocks = []
      @current = nil
    end

    def call
      @source.lines.each_with_index { |line, index| consume(line, index) }
      raise "unclosed Mermaid fence" if @current

      @blocks
    end

    private

    def consume(line, index)
      if @current
        consume_block_line(line)
      elsif line.match?(OPENING_FENCE)
        @current = Block.new(line: index + 1, source: +"")
      end
    end

    def consume_block_line(line)
      if line.match?(CLOSING_FENCE)
        @blocks << @current
        @current = nil
      else
        @current.source << line
      end
    end
  end

  module_function

  def content
    File.read(ARCHITECTURE)
  end

  def opening_fence_count(source = content)
    source.scan(OPENING_FENCE).size
  end

  def blocks(source = content)
    Extractor.new(source).call
  end

  def section(title, level:)
    lines = content.lines
    start = section_start(lines, title, level)
    lines.drop(start + 1).take_while { |line| inside?(line, level) }.join
  end

  def section_start(lines, title, level)
    heading = "#{'#' * level} #{title}"
    start = lines.index { |line| line.chomp == heading }
    return start if start

    raise "missing section: #{title}"
  end

  def inside?(line, level)
    marks = line.match(/\A(?<marks>#+)[ \t]+/)&.[](:marks)
    !marks || marks.length > level
  end

  def label(block)
    "ARCHITECTURE.md:#{block.line}"
  end

  def required_sections
    [
      section("Processing Pipeline", level: 2),
      section("Registry Pattern (Notation::Mermaid)", level: 3),
    ]
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
    expect(described_class.required_sections.map do |section|
      described_class.blocks(section).size
    end)
      .to eq([1, 1])
  end

  described_class.blocks.each do |block|
    it "renders #{described_class.label(block)} as parseable SVG" do
      document = REXML::Document.new(Sirena.render(block.source))

      expect(document.root.name).to eq("svg")
    end
  end
end
