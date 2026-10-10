# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::CaptureString do
  # Parslet captures an empty quoted string as `[]`; each row feeds one
  # through a parser and reads back the label the builder produced.
  rows = [
    ["sequence participant alias falls back to the id",
     Sirena::Parser::Sequence,
     "sequenceDiagram\n  participant A as \"\"\n  A->>A: hi\n",
     ->(d) { d.participants.first.label }, "A"],
    ["class label falls back to the id",
     Sirena::Parser::ClassDiagram,
     "classDiagram\n  class C1[\"\"]\n",
     ->(d) { d.entities.first.name }, "C1"],
    ["c4 element label is empty",
     Sirena::Parser::C4,
     "C4Context\n  Person(p, \"\")\n",
     ->(d) { d.elements.first.label }, ""],
    ["pie slice label is empty and the slice is kept",
     Sirena::Parser::Pie,
     "pie\n  \"\" : 1\n  \"b\" : 2\n",
     ->(d) { d.slices.map(&:label) }, ["", "b"]],
    ["quadrant axis label is empty",
     Sirena::Parser::Quadrant,
     "quadrantChart\n  x-axis \"\" --> R\n",
     :x_axis_left.to_proc, ""],
  ]

  rows.each do |name, parser, source, reader, expected|
    it name do
      expect(reader.call(parser.new.parse(source))).to eq(expected)
    end
  end
end
