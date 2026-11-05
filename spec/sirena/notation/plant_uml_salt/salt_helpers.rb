# frozen_string_literal: true

require "rexml/document"

# Shared helpers for the salt notation specs.
module SaltHelpers
  FIXTURES = File.expand_path("../../../fixtures/plantuml_salt", __dir__)

  def fixture_paths
    Dir[File.join(FIXTURES, "*.salt")]
  end

  def parse_salt(source)
    Sirena::Notation::PlantUMLSalt::Parser.new.parse(source)
  end

  # The elements the diagram draws, not the white canvas behind it.
  def drawn(doc, name)
    doc.get_elements("//#{name}").reject do |element|
      element.attributes["stroke"] == "none"
    end
  end

  def svg_texts(svg)
    REXML::Document.new(svg).get_elements("//text").map(&:text)
  end

  def widgets(block)
    block.rows.flat_map(&:cells)
      .grep_v(Sirena::Notation::PlantUMLSalt::Block)
  end

  # The text each cell of a corpus table row should show, markup removed.
  def cell_texts(source)
    source.lines.grep(/\A\s*\+/).flat_map { |line| line.split("|") }
      .map { |cell| plain_cell(cell) }
      .reject { |cell| cell.empty? || cell == "." }
  end

  def plain_cell(cell)
    cell.gsub(%r{\A[\s+]+|</?b>|\s+\z}, "").gsub(/\s+/, " ")
  end

  # Whether every needle occurs in the haystack, each after the one before.
  def in_order?(needles, haystack)
    cursor = 0
    needles.all? do |needle|
      found = haystack.index(needle, cursor)
      cursor = found + needle.length if found
      found
    end
  end
end
