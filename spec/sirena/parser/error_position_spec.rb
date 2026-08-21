# frozen_string_literal: true

require "English"
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

    it "counts from the stripped source, not the original" do
      # Architecture strips its input before parsing, so its positions are
      # relative to the stripped source. Dropping the strip would fix that
      # but also change which inputs parse at all — String#strip removes
      # \v, \f and \r, which the grammar does not. Accepting the same
      # sources matters more than counting blank lines, so the offset stays
      # as a known gap rather than a fix.
      offset = error_from(Sirena::Parser::Architecture.new,
                          "\n\narchitecture-beta\n  group a(cloud)[A]\n  !!!\n")

      expect(position_in(offset)).to start_with("line 3,")
    end

    ["\varchitecture-beta\f", "architecture-beta\r",
     "\n\narchitecture-beta\n"].each do |source|
      it "still accepts #{source.inspect}, as main does" do
        expect { Sirena::Parser::Architecture.new.parse(source) }
          .not_to raise_error
      end
    end
  end

  describe "columns count characters, not bytes" do
    it "counts a multibyte character on an EARLIER line correctly" do
      # This is the case that discriminates. Measuring the preceding lines
      # in characters instead of bytes, or slicing the failing line by
      # characters instead of bytes, both report column 7 here.
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\nA[é]\nB[é] qux\n")

      expect(message).to start_with("Parse error at line 3, column 6:")
    end

    it "reports the whole message consistently past a multibyte character" do
      # Parslet counts bytes, so "A[é]-->" reported column 9 for a 7
      # character line. Asserted on the full message: the heading and the
      # appended parslet text used to disagree, saying column 8 and char 9.
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\nA[é]-->")

      expect(message).to eq(
        "Parse error at line 2, column 8:\nA[é]-->\n       ^\n" \
        "Premature end of input"
      )
    end
  end

  describe "a literal mismatch" do
    # Parslet's message is an Array of String and Slice parts for this
    # class of failure, not a String. Interpolating it split the message
    # across lines and printed the slice's byte offset.
    it "renders the message on one line, without a byte offset" do
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\nA-->B\nxyzzy qux\n")

      expect(message).to eq(
        "Parse error at line 3, column 7:\nxyzzy qux\n      ^\n" \
        'Expected "\\n", but got "q"'
      )
    end

    # Sources chosen because each one makes parslet return an ARRAY message.
    # The earlier fixtures produced Strings, so reverting the formatter to
    # cause.message passed every example and proved nothing.
    {
      "block" => [Sirena::Parser::BlockParser,
                  "block-beta\nxyzzy qux\n", 'Expected "\\n", but got "q"'],
      "class diagram" => [Sirena::Parser::ClassDiagramParser,
                          "classDiagram\nxyzzy qux\n",
                          'Expected "\\n", but got "q"'],
      "requirement" => [Sirena::Parser::RequirementParser,
                        "requirementDiagram\nelement xyzzy qux\n",
                        'Expected "{", but got "q"'],
      "architecture" => [Sirena::Parser::Architecture,
                         "architecture-beta\ngroup a x\n",
                         'Expected "\\n", but got "x"']
    }.each do |name, (klass, source, expected)|
      it "renders #{name}'s array message as parslet would" do
        message = error_from(klass.new, source)

        expect(message.lines.last.chomp).to eq(expected)
        expect(message).not_to match(/@\d+/)
      end
    end
  end

  describe "a failure at end of input" do
    it "says so and still draws the caret" do
      # The failure sits one line past the source, so there is no line to
      # quote. The heading used to be emitted with nothing under it.
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\nA-->B\nC-->\n")

      expect(message).to eq(
        "Parse error at line 4, column 1:\n(end of input)\n^\n" \
        "Premature end of input"
      )
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
        parser = klass.new
        allow(parser).to receive(:failure_position).and_raise("boom")

        # The fallback has no heading, so it keeps parslet's own position
        # rather than dropping it as the normal path does.
        expect { parser.parse("!!!\n") }
          .to raise_error(
            Sirena::Parser::ParseError,
            "Parse error: Premature end of input at line 1 char 1."
          )

        # Asserted after the fact: a future edit that stops calling
        # failure_position would otherwise pass without ever reaching the
        # fallback this example exists to cover.
        expect(parser).to have_received(:failure_position).once
      end
    end
  end

  describe "when the failure really is at the start" do
    it "still reports line 1, column 1" do
      message = error_from(Sirena::Parser::FlowchartParser.new, "!!!\n")

      expect(position_in(message)).to eq("line 1, column 1")
    end
  end

  # The message is printed, so the caret has to line up with the character
  # the column names once tabs are expanded.
  describe "the caret" do
    it "carries a tab through rather than counting it as one column" do
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\n\tA[ok] qux\n")
      quoted, caret = message.lines[1, 2].map(&:chomp)

      expect(caret).to eq("\t      ^")
      expect(quoted[caret.index("^")]).to eq("q")
    end

    it "still pads with spaces when the line has none" do
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\nA[ok] qux\n")

      expect(message.lines[2].chomp).to eq("      ^")
    end
  end

  # A library has no business reading the caller's global separators.
  describe "the record and field separators" do
    around do |example|
      record = $INPUT_RECORD_SEPARATOR
      field = $OUTPUT_FIELD_SEPARATOR
      example.run
    ensure
      $INPUT_RECORD_SEPARATOR = record
      $OUTPUT_FIELD_SEPARATOR = field
    end

    # This source discriminates where a simpler one cannot: it has two
    # preceding lines for the offset arithmetic, a failing line that ends
    # in a newline for `chomp`, and a literal mismatch, which is the class
    # of failure whose parslet message is a multi-part Array.
    let(:source) { "graph TD\nA-->B\nxyzzy qux\n" }

    it "reports the same message with $/ set to nil" do
      expected = error_from(Sirena::Parser::FlowchartParser.new, source)

      $INPUT_RECORD_SEPARATOR = nil

      expect(error_from(Sirena::Parser::FlowchartParser.new, source))
        .to eq(expected)
    end

    it "reports the same message with $, set" do
      expected = error_from(Sirena::Parser::FlowchartParser.new, source)

      $OUTPUT_FIELD_SEPARATOR = "|"

      expect(error_from(Sirena::Parser::FlowchartParser.new, source))
        .to eq(expected)
    end
  end

  # Parslet's message parts are a String, a Slice, or — for a lookahead —
  # something else again. Quoting the third case the way a Slice is quoted
  # would print the symbol as a string literal.
  describe "a lookahead failure" do
    it "names the atom without quoting it" do
      message = error_from(Sirena::Parser::FlowchartParser.new,
                           "graph TD\nstyle A ")

      expect(message).to end_with("Input should not start with LINE_END")
      expect(position_in(message)).to eq("line 2, column 9")
    end
  end
end
