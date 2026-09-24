# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::Requirement do
  let(:parser) { described_class.new }

  describe '#parse' do
    context 'with basic requirement diagram' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement test_req {
              id: 1
              text: the test text.
              risk: high
              verifymethod: test
              }

              element test_entity {
              type: simulation
              }

              test_entity - satisfies -> test_req
        MERMAID
      end

      it 'parses the diagram successfully' do
        result = parser.parse(source)

        expect(result).to be_a(Sirena::Diagram::Requirement)
        expect(result.requirements.size).to eq(1)
        expect(result.elements.size).to eq(1)
        expect(result.relationships.size).to eq(1)
      end

      it 'parses requirement properties correctly' do
        result = parser.parse(source)
        req = result.requirements.first

        expect(req.name).to eq('test_req')
        expect(req.type).to eq('requirement')
        expect(req.id).to eq('1')
        expect(req.text).to eq('the test text.')
        expect(req.risk).to eq('high')
        expect(req.verifymethod).to eq('test')
      end

      it 'parses element properties correctly' do
        result = parser.parse(source)
        elem = result.elements.first

        expect(elem.name).to eq('test_entity')
        expect(elem.type).to eq('simulation')
      end

      it 'parses relationships correctly' do
        result = parser.parse(source)
        rel = result.relationships.first

        expect(rel.source).to eq('test_entity')
        expect(rel.target).to eq('test_req')
        expect(rel.type).to eq('satisfies')
      end
    end

    context 'with empty diagram' do
      let(:source) { "requirementDiagram\n" }

      it 'parses successfully' do
        result = parser.parse(source)

        expect(result).to be_a(Sirena::Diagram::Requirement)
        expect(result.requirements).to be_empty
        expect(result.elements).to be_empty
        expect(result.relationships).to be_empty
      end
    end

    context 'with multiple requirement types' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              functionalRequirement func_req {
              id: 1
              text: functional requirement
              }

              performanceRequirement perf_req {
              id: 2
              text: performance requirement
              }
        MERMAID
      end

      it 'parses different requirement types' do
        result = parser.parse(source)

        expect(result.requirements.size).to eq(2)
        expect(result.requirements[0].type).to eq('functionalRequirement')
        expect(result.requirements[1].type).to eq('performanceRequirement')
      end
    end

    context 'with all relationship types' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement req1 {
              id: 1
              }

              requirement req2 {
              id: 2
              }

              element elem1 {
              type: test
              }

              req1 - contains -> req2
              req1 - copies -> req2
              req1 - derives -> req2
              elem1 - satisfies -> req1
              elem1 - verifies -> req1
              req2 - refines -> req1
              req2 - traces -> req1
        MERMAID
      end

      it 'parses all relationship types' do
        result = parser.parse(source)

        expect(result.relationships.size).to eq(7)

        types = result.relationships.map(&:type)
        expect(types).to include('contains', 'copies', 'derives', 'satisfies', 'verifies', 'refines', 'traces')
      end
    end

    context 'with styling' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement req1 {
              id: 1
              }

              style req1 fill:#f9f,stroke:#333
        MERMAID
      end

      it 'parses styling directives' do
        result = parser.parse(source)

        expect(result.styles.size).to eq(1)
        style = result.styles.first
        expect(style.fill).to eq('#f9f')
        expect(style.stroke).to eq('#333')
      end
    end

    context 'with class definitions' do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement req1 {
              id: 1
              }

              classDef myClass fill:#f96
              class req1 myClass
        MERMAID
      end

      it 'parses class definitions and assignments' do
        result = parser.parse(source)

        expect(result.classes.size).to eq(1)
        expect(result.class_assignments.size).to eq(1)

        klass = result.classes.first
        expect(klass.name).to eq('myClass')
        expect(klass.fill).to eq('#f96')
      end
    end

    context 'with accessibility title and single-line description (corpus 004)' do
      let(:source) do
        <<~MERMAID
          requirementDiagram
                accTitle: my title
                accDescr: my description
                element test_name {
                type: test_type
                docref: test_ref
                }
        MERMAID
      end

      it 'parses accTitle and accDescr' do
        result = parser.parse(source)

        expect(result.acc_title).to eq('my title')
        expect(result.acc_description).to eq('my description')
        expect(result.elements.size).to eq(1)
      end
    end

    # Not corpus 005 itself: that fixture's body is an uninterpolated
    # `${expectedAccDescription}` template literal (an extraction artifact,
    # per CLAUDE.md), so it stays classified as unsupported. This exercises
    # the same multi-line accDescr {} grammar path with real text instead.
    context 'with accessibility title and multiline description (shape of corpus 005)' do
      let(:source) do
        <<~MERMAID
          requirementDiagram
                accTitle: my title
                accDescr {
                  my multiline
                  description
                }
                element test_name {
                type: test_type
                docref: test_ref
                }
        MERMAID
      end

      it 'parses accTitle and multiline accDescr' do
        result = parser.parse(source)

        expect(result.acc_title).to eq('my title')
        expect(result.acc_description).to include('my multiline')
        expect(result.elements.size).to eq(1)
      end
    end

    context 'with a genuinely empty accDescr {} value' do
      # Verified against mermaid 11.12.0: "accDescr {}" parses to an empty
      # description there, unlike a trailing "accTitle:"/"accDescr:" above
      # (that colon form has no empty value in real mermaid; this brace
      # form does). Parslet returns an empty Array, not an empty String,
      # for a zero-length `.repeat.as(...)` capture -- `[].to_s` is
      # literally "[]" -- so acc_value in builders/requirement.rb must
      # route around it or "" comes back as the 2-character string "[]".
      it 'parses the value as an empty string, not the literal text "[]"' do
        source = "requirementDiagram\naccDescr {}\n"

        result = parser.parse(source)

        expect(result.acc_description).to eq('')
      end
    end

    context 'with a trailing accTitle directive and nothing after it' do
      # Keep this: it is the only check on `.repeat(1)` (not `.repeat`) in
      # acc_title_declaration's value token, verified by reverting just that
      # one line -- it goes red on its own. A whole-file revert to before
      # accTitle support existed at all stays green here too (no accTitle
      # rule means the same ParseError for an unrelated reason), so this
      # becomes the only check once a later change re-adds acc_title support
      # in a way that loses the `.repeat(1)` minimum again.
      it 'raises a parse error, matching real mermaid' do
        # Verified against mermaid 11.12.0: "accTitle:\n" with nothing
        # following is a parse error there, not an empty title -- the
        # lexer's `\s*` only skips leading blank lines before a MANDATORY
        # value token. An earlier version of this grammar used `.repeat`
        # (0+) here and silently accepted this as an empty string, which
        # is a value mermaid can never actually produce.
        source = "requirementDiagram\naccTitle:\n"

        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    context 'with NBSP separating the accessibility keyword from its value' do
      # Verified against mermaid 11.12.0: `\s` in the accTitle/accDescr
      # lexer tokens strips a leading U+00A0 (NBSP) like any other
      # separator, so the value itself never starts with one. NBSP is a
      # realistic input, not a contrived one -- it's what a paste from a
      # word processor or a browser leaves behind.
      it 'strips a leading NBSP instead of keeping it as part of acc_title' do
        source = "requirementDiagram\naccTitle:  My title\n"

        result = parser.parse(source)

        expect(result.acc_title).to eq('My title')
      end
    end

    context 'with JavaScript whitespace around accessibility delimiters' do
      {
        'a vertical tab' => "\v",
        'a form feed' => "\f",
        'a no-break space' => "\u00A0",
        'an ogham space mark' => "\u1680",
        'an en quad' => "\u2000",
        'a line separator' => "\u2028",
        'a paragraph separator' => "\u2029",
        'a narrow no-break space' => "\u202F",
        'a medium mathematical space' => "\u205F",
        'an ideographic space' => "\u3000",
        'a zero-width no-break space' => "\uFEFF"
      }.each do |label, gap|
        it "accepts #{label} in each accessibility opener" do
          source = "requirementDiagram\n" \
                   "accTitle#{gap}: Title\n" \
                   "accDescr#{gap}: Description\n"
          result = parser.parse(source)

          expect(result.acc_title).to eq('Title')
          expect(result.acc_description).to eq('Description')

          result = parser.parse("requirementDiagram\naccDescr#{gap}{Block}\n")
          expect(result.acc_description).to eq('Block')
        end
      end

      it 'does not count a next-line character as whitespace' do
        source = "requirementDiagram\naccTitle\u0085: Title\n"

        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end

      it 'trims JavaScript whitespace from every accessibility value form' do
        [
          ["accTitle: Title\uFEFF", :acc_title, 'Title'],
          ["accDescr: Description\uFEFF", :acc_description, 'Description'],
          ["accDescr {Block\uFEFF}", :acc_description, 'Block']
        ].each do |directive, attribute, expected|
          result = parser.parse("requirementDiagram\n#{directive}\n")

          expect(result.public_send(attribute)).to eq(expected)
        end
      end
    end

    context 'with percent-prefixed accessibility text' do
      it 'keeps a same-line %% sequence as title or description text' do
        source = "requirementDiagram\n" \
                 "accTitle: %% title\n" \
                 "accDescr: %% description\n"

        result = parser.parse(source)

        expect(result.acc_title).to eq('%% title')
        expect(result.acc_description).to eq('%% description')
      end

      it 'keeps a leading %% line inside a braced description' do
        source = "requirementDiagram\naccDescr {\n%% note\nactual\n}\n"

        result = parser.parse(source)

        expect(result.acc_description).to eq("%% note\nactual")
      end
    end

    context 'with an unreadable source encoding' do
      it 'reports a valid non-UTF-8 accessibility value as a ParseError' do
        source = (+"requirementDiagram\naccTitle: \xA3\n").force_encoding(Encoding::ISO_8859_1)
        expect(source).to be_valid_encoding

        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end

      it 'reports invalid UTF-8 as a ParseError' do
        source = (+"requirementDiagram\naccTitle: \xFF\n").force_encoding(Encoding::UTF_8)
        expect(source.valid_encoding?).to be(false)

        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    context 'with the accessibility keyword and its value separated by a newline' do
      # Mermaid's lexer token is `accTitle\s*":"\s*` / `accDescr\s*":"\s*` --
      # `\s` matches a newline, so the colon and the value after it may
      # start on the line following the keyword. Verified against the
      # installed mermaid grammar (requirementDiagram.jison lines 19-22).
      it 'parses accTitle when the colon and value are on their own lines' do
        source = "requirementDiagram\naccTitle:\nNext title\n"

        result = parser.parse(source)

        expect(result.acc_title).to eq('Next title')
      end

      it 'parses accDescr when the opening brace is on its own line' do
        source = "requirementDiagram\naccDescr\n{\nDesc\n}\n"

        result = parser.parse(source)

        expect(result.acc_description).to eq('Desc')
      end
    end

    context 'with a statement immediately after a multiline accDescr closing brace' do
      # requirementDiagram.jison's multiline accDescr body state is popped
      # by `}` alone -- the grammar never requires a NEWLINE token after
      # it, so another directive may start on the same line.
      it 'parses both directives' do
        source = "requirementDiagram\naccDescr {Desc}accTitle: T\n"

        result = parser.parse(source)

        expect(result.acc_description).to eq('Desc')
        expect(result.acc_title).to eq('T')
      end
    end

    context 'with a comment between the accessibility keyword and its colon' do
      # Mermaid's lexer token for this directive is the single regex
      # `accTitle\s*":"\s*` -- `\s` never matches `%%`, and there is no
      # separate rule for a comment inside that token, so real mermaid
      # cannot parse this as an accTitle directive at all. The newline-
      # crossing fix must stay whitespace-only here, not comment-aware,
      # or it silently accepts an input mermaid rejects.
      #
      # Keep this: it is the only check that acc_title_declaration uses
      # `whitespace?` and not the comment-aware `ws?` between "accTitle" and
      # the colon, verified by swapping just that one occurrence -- it goes
      # red on its own. A whole-file revert to before accTitle support
      # existed stays green here too (no accTitle rule means the same
      # ParseError for an unrelated reason).
      it 'raises a parse error rather than skipping the comment' do
        source = "requirementDiagram\naccTitle%% c\n: T\nelement foo {\ntype: bar\n}\n"

        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end
  end
end
