# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Base do
  # The positioning helpers live here; the examples drive them through the
  # five parsers that report a position.
  # Every one of these reported "line 1, column 1" before, whatever the
  # input, because `Parslet::Source#line_and_column` was called with no
  # argument and read a bytepos parslet had already rewound to 0.
  def position_in(message)
    message[/line (\d+), column (\d+)/, 0]
  end

  def error_from(parser, source)
    parser.parse(source)
    raise "expected #{parser.class} to reject the source"
  rescue Sirena::Parser::ParseError => e
    e.message
  end

  {
    "flowchart" => [
      Sirena::Parser::FlowchartParser, "graph TD\nA-->B\nC-->\n", 4
    ],
    "block" => [
      Sirena::Parser::BlockParser, "block-beta\n  columns 3\n  ((((\n", 3
    ],
    "class diagram" => [
      Sirena::Parser::ClassDiagramParser, "classDiagram\n  class C1\n  ((((\n", 3
    ],
    "requirement" => [
      Sirena::Parser::RequirementParser, "requirementDiagram\n  !!!!\n", 2
    ]
  }.each do |name, (klass, source, line)|
    it "reports the failing line for #{name}" do
      message = error_from(klass.new, source)

      expect(position_in(message)).to start_with("line #{line},")
    end
  end

  describe "architecture" do
    # It used to strip its input before parsing and then report against the
    # stripped string, so leading blank lines silently shifted every number.
    it "counts leading blank lines" do
      source = "\n\narchitecture-beta\n  group a(cloud)[A]\n  !!!\n"

      message = error_from(Sirena::Parser::Architecture.new, source)

      expect(position_in(message)).to start_with("line 5,")
    end
  end

  describe "the deepest cause, not the outer one" do
    it "reports where the input ran out, not where the statement began" do
      # Statements are optional and backtrack, so parslet's outer cause
      # points at the boundary it gave up on — line 2 column 1 here. The
      # deepest cause points just past "A-->", which is the useful answer.
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\nA-->")

      expect(position_in(message)).to eq("line 2, column 5")
    end
  end

  describe "when the failure really is at the start" do
    it "still reports line 1, column 1" do
      message = error_from(Sirena::Parser::FlowchartParser.new, "!!!\n")

      expect(position_in(message)).to eq("line 1, column 1")
    end
  end
end
