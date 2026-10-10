# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Base do
  describe "parsers declared as a grammar and builder pair" do
    # Valid input, the diagram class it must produce, and an input whose
    # failure is on line 2 of a source that otherwise starts correctly.
    declared = {
      Sirena::Parser::C4 => ["C4Context\ntitle My System", Sirena::Diagram::C4,
                             "C4Context\n???"],
      Sirena::Parser::Info => ["info", Sirena::Diagram::Info,
                               "info\n???"],
      Sirena::Parser::Pie => ["pie\n  \"Apples\" : 42", Sirena::Diagram::Pie,
                              "pie\n???"],
      Sirena::Parser::Quadrant => ["quadrantChart\n  title T", Sirena::Diagram::Quadrant,
                                   "quadrantChart\n???"],
      Sirena::Parser::Sequence => ["sequenceDiagram\nAlice->>Bob: Hello",
                                   Sirena::Diagram::Sequence,
                                   "sequenceDiagram\n???"],
      Sirena::Parser::Gantt => ["gantt\n  title T", Sirena::Diagram::Gantt,
                                "gantt\n???"],
      Sirena::Parser::Sankey => ["sankey-beta\nA,B,10", Sirena::Diagram::Sankey,
                                 "sankey-beta\n???"],
      Sirena::Parser::Timeline => ["timeline\n  title T\n  2002 : LinkedIn",
                                   Sirena::Diagram::Timeline,
                                   "timeline\n:"],
      Sirena::Parser::Error => ["error", Sirena::Diagram::Error,
                                "error\n???"],
      Sirena::Parser::ErDiagram => ["erDiagram\nCUSTOMER ||--o{ ORDER : places",
                                    Sirena::Diagram::ErDiagram,
                                    "erDiagram\n???"],
    }

    declared.each do |parser_class, (valid, diagram_class, invalid)|
      describe parser_class do
        it "parses valid input to #{diagram_class}" do
          expect(parser_class.new.parse(valid)).to be_a(diagram_class)
        end

        it "reports a syntax error with line, column and the source line" do
          source_line = Regexp.escape(invalid.lines[1])
          expect { parser_class.new.parse(invalid) }.to raise_error(
            Sirena::Parser::ParseError,
            /\AParse error at line 2, column \d+:\n#{source_line}\n/,
          )
        end
      end
    end
  end

  describe ".grammar and .builder" do
    it "inherits the builder from the parent parser" do
      expect(Class.new(Sirena::Parser::Pie).builder)
        .to eq(Sirena::Parser::Builders::Pie)
    end

    it "has no builder when nothing in the chain declares one" do
      expect(described_class.builder).to be_nil
    end

    it "raises NotImplementedError when a subclass declares nothing" do
      expect { Class.new(described_class).new.parse("x") }
        .to raise_error(NotImplementedError, /must declare grammar and builder/)
    end
  end
end
