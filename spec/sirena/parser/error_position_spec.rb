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
    it "reports the failing line" do
      source = "architecture-beta\n  group a(cloud)[A]\n  !!!\n"

      message = error_from(Sirena::Parser::Architecture.new, source)

      expect(position_in(message)).to start_with("line 3,")
    end

    it "does not count leading blank lines, and still accepts \\v and \\f" do
      # Architecture strips its input before parsing, so its positions are
      # relative to the stripped source. Dropping the strip would fix that
      # but also change which inputs parse at all — String#strip removes
      # \v, \f and \r, which the grammar does not. Accepting the same
      # sources matters more than counting blank lines, so the offset stays
      # as a known gap rather than a fix.
      offset = error_from(Sirena::Parser::Architecture.new,
                          "\n\narchitecture-beta\n  group a(cloud)[A]\n  !!!\n")

      expect(position_in(offset)).to start_with("line 3,")
      expect { Sirena::Parser::Architecture.new.parse("\varchitecture-beta\f") }
        .not_to raise_error
    end
  end

  describe "columns count characters, not bytes" do
    it "places the column past a multibyte character correctly" do
      # Parslet counts bytes, so "A[é]-->" reported column 9 for a 7
      # character line — the caret landed a character too far right.
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\nA[é]-->")

      expect(position_in(message)).to eq("line 2, column 8")
    end
  end

  describe "the fallback message" do
    # format_parse_error rescues StandardError and reports a bare message.
    # That handler interpolated a variable the rename had removed, so
    # entering it raised NameError instead of reporting anything. Driven by
    # making the real handler fail from the inside, not by replacing it —
    # a stubbed-out formatter never executes the line that was broken.
    [
      Sirena::Parser::FlowchartParser,
      Sirena::Parser::BlockParser,
      Sirena::Parser::RequirementParser
    ].each do |klass|
      it "reports rather than raising NameError for #{klass}" do
        allow_any_instance_of(described_class)
          .to receive(:failure_position).and_raise("boom")

        expect { klass.new.parse("!!!\n") }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end
    end
  end

  describe "when the failure really is at the start" do
    it "still reports line 1, column 1" do
      message = error_from(Sirena::Parser::FlowchartParser.new, "!!!\n")

      expect(position_in(message)).to eq("line 1, column 1")
    end
  end
end
