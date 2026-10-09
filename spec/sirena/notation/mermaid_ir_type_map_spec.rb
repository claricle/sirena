# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::Mermaid do
  def map_path
    File.expand_path("../../../docs/ir-type-map.md", __dir__)
  end

  def row_pattern
    Regexp.new(
      "\\A\\| `(?<type>[^`]+)` \\| `(?<shape>[^`]+)` " \
      "\\| `(?<path>[^`]+)` \\| (?<evidence>.+) \\|\\z",
    )
  end

  def rows
    File.readlines(map_path, chomp: true).filter_map do |line|
      match = row_pattern.match(line)
      match&.named_captures
    end
  end

  def implementation_path(row)
    File.expand_path("../../../#{row.fetch('path')}", __dir__)
  end

  it "maps every registered Mermaid type exactly once" do
    mapped_types = rows.map { |row| row.fetch("type").to_sym }
    registered_types = Sirena::Notation::Mermaid::TYPES.keys

    expected_types = registered_types.to_h { |type| [type, 1] }

    expect(mapped_types.tally).to eq(expected_types)
  end

  it "uses only the three settled shapes" do
    shapes = %w[data-shaped graph-shaped pre-positioned]

    expect(rows.map { |row| row.fetch("shape") }.uniq - shapes).to be_empty
  end

  it "points every row at an existing implementation" do
    paths = rows.map { |row| implementation_path(row) }

    expect(paths).to all(satisfy { |path| File.file?(path) })
  end

  it "gives every row nonempty evidence" do
    evidence = rows.map { |row| row.fetch("evidence").strip }

    expect(evidence).to all(satisfy { |value| !value.empty? })
  end
end
