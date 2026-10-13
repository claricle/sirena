# frozen_string_literal: true

require "spec_helper"

module ErTildeChunkSpecHelpers
  def single_line_tilde_type
    "erDiagram\nRENTAL {\n  ~timestamp with time zone~ rental_date\n}\n"
  end

  def multiline_tilde_type
    "erDiagram\nRENTAL {\n  ~timestamp\nwith time zone~ rental_date\n}\n"
  end

  def tilde_mismatches(samples)
    samples.filter_map { |length, input| tilde_run_difference(length, input) }
  end

  def tilde_grammar
    @tilde_grammar ||= Sirena::Parser::Grammars::ErDiagram.new
  end

  def tilde_lexer_regex
    @tilde_lexer_regex ||= Regexp.new(
      "\\A(?:~(?:[^~\n\r\u2028\u2029]*~)+)", Regexp::MULTILINE
    )
  end

  def random_tilde_samples
    random = Random.new(20_260_929)
    lengths = random_tilde_lengths(random)
    lengths.map do |length|
      [length, "~#{random_tilde_body(length, random)}"]
    end
  end

  def random_tilde_lengths(random)
    Array.new(40) { random.rand(1..20) } +
      Array.new(40) { random.rand(49_990..50_010) } +
      Array.new(20) { random.rand(1..150_000) }
  end

  def random_tilde_body(length, random)
    broad = ("a".."z").to_a + ("0".."9").to_a + ["-", ".", "/", "_"]
    noise = [" ", "!", "@"]
    Array.new(length) { random_tilde_character(random, broad, noise) }.join
  end

  def random_tilde_character(random, broad, noise)
    return "~" if random.rand(15).zero?

    pool = random.rand(20) < 19 ? broad : noise
    pool.sample(random: random)
  end

  def tilde_run_difference(length, input)
    expected = tilde_lexer_regex.match(input)&.to_s
    parsed = parsed_tilde_input(input)
    return if parsed == expected

    { length: length, expected: expected&.length, got: parsed&.length }
  end

  def parsed_tilde_input(input)
    tilde_grammar.tilde_marked_run.parse(input, prefix: true).to_s
  rescue Parslet::ParseFailed
    nil
  end
end

RSpec.describe Sirena::Parser::ErDiagram do
  include ErTildeTiming
  include ErTildeChunkSpecHelpers

  let(:parser) { described_class.new }

  describe "#parse" do
    # Verified against mermaid 11.16.1's lexer regex for this token --
    # `/^(?:([^\s]*)[~].*[~]([^\s]*))/i`, no `/s` flag -- `.` cannot cross
    # a newline in a JS regex without that flag, so mermaid never treats
    # this as one tilde-quoted type spanning the break. Sirena's grammar
    # must refuse it too, not silently accept a newline inside the tildes.
    context "when parsing simple ER diagram with relationship" do
      let(:source) { "erDiagram\nCUSTOMER ||--o{ ORDER" }
      let(:diagram) { parser.parse(source) }

      it "retains diagram" do
        expect(diagram).to be_a(Sirena::Diagram::ErDiagram)
      end

      it "retains diagram.entities.length" do
        expect(diagram.entities.length).to eq(2)
      end

      it "retains diagram.relationships.length" do
        expect(diagram.relationships.length).to eq(1)
      end
    end

    context "when parsing non-identifying relationship" do
      let(:source) { "erDiagram\nCUSTOMER ||--o{ ORDER" }
      let(:diagram) { parser.parse(source) }

      it "retains rel.from_id" do
        rel = diagram.relationships.first

        expect(rel.from_id).to eq("CUSTOMER")
      end

      it "retains rel.to_id" do
        rel = diagram.relationships.first

        expect(rel.to_id).to eq("ORDER")
      end

      it "retains rel.relationship_type" do
        rel = diagram.relationships.first

        expect(rel.relationship_type).to eq("non-identifying")
      end

      it "retains rel.cardinality_from" do
        rel = diagram.relationships.first

        expect(rel.cardinality_from).to eq("one")
      end

      it "retains rel.cardinality_to" do
        rel = diagram.relationships.first

        expect(rel.cardinality_to).to eq("zero_or_more")
      end
    end

    it "parses identifying relationship" do
      source = "erDiagram\nCUSTOMER ||==o{ ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.relationship_type).to eq("identifying")
    end

    context "when parsing entity with attributes" do
      let(:source) do
        <<~MERMAID
          erDiagram
          CUSTOMER {
            int id PK
            string name
            string email FK
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains entity" do
        entity = diagram.find_entity("CUSTOMER")

        expect(entity).not_to be_nil
      end

      it "retains entity.attributes.length" do
        entity = diagram.find_entity("CUSTOMER")

        expect(entity.attributes.length).to eq(3)
      end

      it "retains attr1.name" do
        entity = diagram.find_entity("CUSTOMER")
        attr1 = entity.attributes[0]

        expect(attr1.name).to eq("id")
      end

      it "retains attr1.attribute_type" do
        entity = diagram.find_entity("CUSTOMER")
        attr1 = entity.attributes[0]

        expect(attr1.attribute_type).to eq("int")
      end

      it "retains attr1.key_type" do
        entity = diagram.find_entity("CUSTOMER")
        attr1 = entity.attributes[0]

        expect(attr1.key_type).to eq("PK")
      end

      it "retains attr2.name" do
        entity = diagram.find_entity("CUSTOMER")
        attr2 = entity.attributes[1]

        expect(attr2.name).to eq("name")
      end

      it "retains attr2.attribute_type" do
        entity = diagram.find_entity("CUSTOMER")
        attr2 = entity.attributes[1]

        expect(attr2.attribute_type).to eq("string")
      end

      it "retains attr2.key_type" do
        entity = diagram.find_entity("CUSTOMER")
        attr2 = entity.attributes[1]

        expect(attr2.key_type).to be_nil
      end

      it "retains attr3.name" do
        entity = diagram.find_entity("CUSTOMER")
        attr3 = entity.attributes[2]

        expect(attr3.name).to eq("email")
      end

      it "retains attr3.attribute_type" do
        entity = diagram.find_entity("CUSTOMER")
        attr3 = entity.attributes[2]

        expect(attr3.attribute_type).to eq("string")
      end

      it "retains attr3.key_type" do
        entity = diagram.find_entity("CUSTOMER")
        attr3 = entity.attributes[2]

        expect(attr3.key_type).to eq("FK")
      end
    end

    # A type name that isn't a bare identifier -- mermaid accepts a
    # `~...~`-quoted one. Corpus case unknown/yari2-dc83acff.mmd.
    context "when parsing an attribute with a tilde-quoted multi-word " \
            "type" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            ~timestamp with time zone~ rental_date "NN"
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains attr.name" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.name).to eq("rental_date")
      end

      it "retains attr.attribute_type" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.attribute_type).to eq("<timestamp with time zone>")
      end
    end

    # A quoted note after the key type -- mermaid renders it as the
    # attribute's comment (its own `attribute-comment` SVG column,
    # verified against spec/mermaid/unknown/yari2-dc83acff.svg). It
    # must reach the model, not just be consumed and dropped by the
    # grammar -- the renderer spec proves it reaches the rendered SVG too.
    context "when carries the quoted note after the key type into the " \
            "model" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            int rental_id PK "NN"
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains attr.name" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.name).to eq("rental_id")
      end

      it "retains attr.key_type" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.key_type).to eq("PK")
      end

      it "retains attr.note" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.note).to eq("NN")
      end
    end

    # An empty quoted note, `""`, comes back from `GreedyRun` as a real
    # empty `Parslet::Slice` (`[^"]*` can match zero characters), not the
    # `[]` a native `.repeat.as(:string)` capture would produce on no
    # match -- `extract_text` (`builders/er_diagram.rb`) relies on that
    # guarantee and calls `.to_s` on it directly.
    describe "carries an empty quoted note as an empty string, " \
             "not the literal \"[]\"" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            int rental_id PK ""
          }
        MERMAID
      end

      let(:diagram) do
        parser.parse(source)
      end

      let(:attr) do
        diagram.find_entity("RENTAL").attributes.first
      end

      before do
        source
        diagram
        attr
      end

      it "preserves property 1" do
        expect(attr.note).to eq("")
      end
    end

    # Mermaid's ER `COMMENT` token accepts only double-quoted text with no
    # embedded quote and no backslash escape -- a Codex review found the
    # note rule reused the shared `string`/`single_quoted_string` grammar
    # (`common.rb`), which accepts BOTH, wrongly parsing text mermaid
    # 11.16.1 rejects outright.
    context "when refusing a single-quoted note the way mermaid does" do
      let(:plain_source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            int rental_id PK "NN"
          }
        MERMAID
      end
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            int rental_id PK 'NN'
          }
        MERMAID
      end

      it "retains plain_attr.note" do
        plain_diagram = parser.parse(plain_source)
        plain_attr = plain_diagram.find_entity("RENTAL").attributes.first

        expect(plain_attr.note).to eq("NN")
      end

      it "rejects the invalid source" do
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    context "when refusing a note with a backslash-escaped quote the way " \
            "mermaid does" do
      let(:plain_source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            int rental_id PK "ab"
          }
        MERMAID
      end
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            int rental_id PK "a\\"b"
          }
        MERMAID
      end

      it "retains plain_attr.note" do
        plain_diagram = parser.parse(plain_source)
        plain_attr = plain_diagram.find_entity("RENTAL").attributes.first

        expect(plain_attr.note).to eq("ab")
      end

      it "rejects the invalid source" do
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    # `GreedyRun` (the atom `tilde_prefix`/`tilde_suffix`/`tilde_marked_run`
    # are built from, grammars/er_diagram.rb) must find the matched run's
    # length in CHARACTERS, not bytes -- `StringScanner#match?` (what
    # `Source#matches?` delegates to) reports bytes, while `Source#consume`
    # advances by characters. A byte count fed to `consume` over-consumes on
    # any multibyte character: a Codex review at this tip found
    # `foo~bar baz~<CJK char> field` came back with type
    # `"foo<bar baz><CJK char> f"` and name `"ield"` -- the multibyte
    # suffix char (3 bytes, 1 character) pulled 2 extra ASCII characters
    # into the type.
    context "when does not over-consume past a multibyte character in the " \
            "tilde suffix" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            foo~bar baz~中 field
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains attr.attribute_type" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.attribute_type).to eq("foo<bar baz>中")
      end

      it "retains attr.name" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.name).to eq("field")
      end
    end

    # Same byte/character bug, prefix side: a multibyte character before
    # the opening tilde must count as one character, not several bytes.
    it "does not over-consume past a multibyte character in the tilde prefix" do
      grammar = Sirena::Parser::Grammars::ErDiagram.new

      expect(grammar.tilde_type.parse("é~foo~")[:string].to_s).to eq("é~foo~")
    end

    # End-to-end regression, not a pin on `GreedyRun.scan`'s own contract
    # (the unit specs in greedy_run_spec.rb do that directly): with no `~`
    # in "string", `tilde_type` always fails and Parslet backtracks to
    # plain `identifier`, so this shape passes regardless of how
    # `tilde_prefix`'s scan behaves on the note's incompatible byte -- it
    # only proves the parser still returns the right `attribute_type` and
    # `note` for an ASCII-8BIT source that happens to hold one.
    describe "extracts a note holding a byte an encoding-fixed tilde " \
             "regex cannot match" do
      let(:source) do
        (+"erDiagram\nCUSTOMER {\n  string name \"note \xFF here\"\n}\n")
          .force_encoding(Encoding::ASCII_8BIT)
      end

      let(:diagram) do
        parser.parse(source)
      end

      let(:attr) do
        diagram.find_entity("CUSTOMER").attributes.first
      end

      before do
        source
        diagram
        attr
      end

      it "preserves property 1" do
        expect(attr.attribute_type).to eq("string")
      end

      it "preserves property 2" do
        expect(attr.note).to eq((+"note \xFF here").force_encoding(Encoding::ASCII_8BIT))
      end
    end

    # Unlike the plain-identifier case above, `List~type~` DOES have a `~`,
    # so `tilde_type` is the alternative that succeeds here -- `attribute_type`
    # never falls back to `identifier`, putting `tilde_prefix`'s own scan of
    # the note's incompatible byte squarely on the path to the result. This
    # end-to-end run is what regressed under the old `''`-on-rescue scan:
    # `tilde_prefix` discarded its already-matched "List" along with the
    # byte, so the whole line failed to parse (`ParseError`, not a wrong
    # value) -- reproduced by hand against the pre-fix code. The scan's own
    # contract (what it returns, not just that the full parse doesn't blow
    # up) is pinned directly by greedy_run_spec.rb.
    describe "parses a tilde-quoted type followed by a note holding " \
             "a byte the tilde regex cannot match" do
      let(:source) do
        (+"erDiagram\nCUSTOMER {\n  " \
          "List~type~ name \"note \xFF here\"\n}\n")
          .force_encoding(Encoding::ASCII_8BIT)
      end

      let(:diagram) do
        parser.parse(source)
      end

      let(:attr) do
        diagram.find_entity("CUSTOMER").attributes.first
      end

      before do
        source
        diagram
        attr
      end

      it "preserves property 1" do
        expect(attr.attribute_type).to eq("List<type>")
      end

      it "preserves property 2" do
        expect(attr.name).to eq("name")
      end

      it "preserves property 3" do
        expect(attr.note).to eq((+"note \xFF here").force_encoding(Encoding::ASCII_8BIT))
      end
    end

    it "refuses a tilde-quoted type whose core holds a byte the same regex " \
       "cannot match" do
      source = (+"erDiagram\nCUSTOMER {\n  List~\xFFtype\xFF~ name\n}\n")
        .force_encoding(Encoding::ASCII_8BIT)

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    # A `Parslet::Slice` built without a line cache raises `ArgumentError`
    # from `#line_and_column` instead of returning a position -- a Codex
    # review at this tip found `GreedyRun`'s hand-built `Slice` omitted it.
    # Starting at position 0 would pass this even with a missing (empty)
    # cache -- an empty cache assumes no newlines exist at all, so it
    # agrees with the real one at [1, 1]. Starting after a real newline
    # makes them disagree: an empty cache reports [1, 3].
    it "keeps a captured tilde type slice able to report its real line and " \
       "column" do
      grammar = Sirena::Parser::Grammars::ErDiagram.new

      result = (Parslet.str("x\n") >> grammar.tilde_type.as(:r))
        .parse("x\n~foo~")

      expect(result[:r][:string].line_and_column).to eq([2, 1])
    end

    it "accepts the single-line positive control for the newline boundary" do
      attr = parser.parse(single_line_tilde_type).find_entity("RENTAL")
        .attributes.first
      expect(attr.attribute_type).to eq("<timestamp with time zone>")
    end

    it "refuses a tilde-quoted type when it spans a newline" do
      expect { parser.parse(multiline_tilde_type) }
        .to raise_error(Sirena::Parser::ParseError)
    end

    # JS `\s` (what `[^\s]*` excludes) is ECMA-262 WhiteSpace, not just
    # space/tab/newline -- it includes U+00A0 (NBSP) and the other
    # Unicode space separators. `tilde_suffix` must stop there too, not
    # swallow an NBSP as if it were an ordinary character. Tested at the
    # grammar rule directly: a full diagram parse would also need `ws`/
    # `space` (inherited from `Grammars::Common`, out of this fix's
    # scope) to treat NBSP as a token separator, which is a separate gap.
    describe 'stops the tilde suffix at an NBSP, matching JS `\s`' do
      let(:grammar) do
        Sirena::Parser::Grammars::ErDiagram.new
      end

      before do
        grammar
      end

      it "preserves property 1" do
        expect(grammar.tilde_suffix.parse("foo").to_s).to eq("foo")
      end

      it "preserves property 2" do
        expect { grammar.tilde_suffix.parse("foo bar") }
          .to raise_error(Parslet::ParseFailed, /Don't know what to do with/)
      end
    end

    # One entry per escape in the grammar's whitespace class (ECMA-262
    # WhiteSpace plus LineTerminator): each must end the run. The code
    # point just outside each range, and next to each lone escape, must
    # not -- so widening the class turns this red as surely as dropping
    # an escape does.
    %w[tilde_prefix tilde_suffix].each do |rule_name|
      context "with #{rule_name}" do
        let(:run_before) do
          rule = Sirena::Parser::Grammars::ErDiagram.new.public_send(rule_name)
          ->(char) { rule.parse("foo#{char}bar", prefix: true).to_s }
        end
        let(:whitespace) do
          ["\t", "\v", "\f", " ", "\u00A0", "\u1680",
           *(0x2000..0x200A).map { |code| [code].pack("U") },
           "\u2028", "\u2029", "\u202F", "\u205F", "\u3000",
           "\uFEFF", "\n", "\r"]
        end
        let(:not_whitespace) do
          ["\b", "\u000E", "\u001F", "!", "\u0085", "\u009F",
           "\u00A1", "\u167F", "\u1681", "\u180E", "\u1FFF",
           "\u200B", "\u2027", "\u202A", "\u202E", "\u2030",
           "\u205E", "\u2060", "\u2FFF", "\u3001", "\uFEFE",
           "\uFF00"]
        end

        it "ends its run at every JS `\\s` character" do
          stuck = whitespace.reject { |char| run_before.call(char) == "foo" }

          expect(stuck.map(&:dump)).to eq([])
        end

        it "does not end its run at any adjacent code point" do
          early = not_whitespace.reject do |char|
            run_before.call(char) == "foo#{char}bar"
          end

          expect(early.map(&:dump)).to eq([])
        end
      end
    end

    # JS's `.` refuses to cross ANY ECMA-262 LineTerminator, not only
    # `\n` -- CR and the Unicode line/paragraph separators (U+2028,
    # U+2029) too. A bare CR inside the tildes must refuse exactly like
    # the `\n` case above, not be silently swallowed as an ordinary char.
    context "when refusing a tilde-quoted type that spans a bare CR" do
      let(:source) { "erDiagram\nRENTAL {\n  ~foo\rbar~ name\n}\n" }

      it "retains no_cr_attr.attribute_type" do
        no_cr_source = "erDiagram\nRENTAL {\n  ~foobar~ name\n}\n"
        no_cr_diagram = parser.parse(no_cr_source)
        no_cr_attr = no_cr_diagram.find_entity("RENTAL").attributes.first

        expect(no_cr_attr.attribute_type).to eq("<foobar>")
      end

      it "rejects the invalid source" do
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    # Same refusal, for the two Unicode line/paragraph separators
    # themselves (U+2028, U+2029) -- checked at the grammar rule directly
    # against the same whole-input reference regex used by the
    # chunk-boundary specs below, not hand-derived.
    ["~a\u2028b~", "~a\u2029b~"].each do |input|
      it "keeps the lexer from matching the separator in #{input.inspect}" do
        expect(tilde_lexer_regex.match(input)).to be_nil
      end

      it "refuses the separator in #{input.inspect}" do
        expect { tilde_grammar.tilde_marked_run.parse(input) }
          .to raise_error(Parslet::ParseFailed)
      end
    end

    # Mermaid's lexer regex has no minimum length between the two tildes
    # (`.*`, not `.+`), so `~~` alone matches as an empty type -- verified
    # by running that regex directly (node) against mermaid's own compiled
    # erDiagram lexer. Sirena's grammar previously required `repeat(1)`,
    # which refused a diagram mermaid renders fine.
    context "when accepts an empty tilde-quoted type" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            ~~ rental_date
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains attr.name" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.name).to eq("rental_date")
      end

      it "retains attr.attribute_type" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.attribute_type).to eq("<>")
      end
    end

    # Mermaid's lexer captures a non-whitespace run directly before the
    # opening tilde and after the closing one, not just `~...~` alone --
    # `foo~bar baz~qux` parses in mermaid as the single type
    # `foo~bar baz~qux`, verified by running mermaid's own erDiagram
    # parser. Codex round-2 finding 1 (ffaabf5d).
    context "when keeps a non-whitespace prefix and suffix around a " \
            "tilde-quoted type" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            foo~bar baz~qux rental_date
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains attr.name" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.name).to eq("rental_date")
      end

      it "retains attr.attribute_type" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.attribute_type).to eq("foo<bar baz>qux")
      end
    end

    # Codex round-2 finding: the greedy inner match (`.*` in mermaid's
    # lexer) lands on the LAST tilde on the line, not the first, so a
    # type with two embedded pairs -- `~bar~baz qux~` and
    # `foo~one~two three~four~five` -- is ONE token, not split at the
    # first closing tilde.
    context "when greedily matches to the last tilde on the line, not the " \
            "first" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            ~bar~baz qux~ name
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains attr.name" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.name).to eq("name")
      end

      it "retains attr.attribute_type" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.attribute_type).to eq("~bar<baz qux>")
      end
    end

    context "when greedily spans multiple embedded tilde pairs across " \
            "spaces" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            foo~one~two three~four~five name
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains attr.name" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.name).to eq("name")
      end

      it "retains attr.attribute_type" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.attribute_type).to eq("foo<one<two three>four>five")
      end
    end

    # A comma inside a generic's tildes (`Map~K, V~`) splits the type text
    # into three parts before `process_tilde_set` ever runs, so
    # `should_combine_tilde_sets?` must rejoin them. Expected value taken
    # by running mermaid's own `parseGenericTypes` (packages/mermaid/src/
    # diagrams/common/common.ts, verified against the compiled function in
    # node_modules/mermaid/dist/mermaid.js) on the identical input, not
    # hand-derived.
    context "when rejoins a comma inside a single tilde-quoted generic " \
            "type" do
      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            Map~K, V~ rental_date
          }
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains attr.name" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.name).to eq("rental_date")
      end

      it "retains attr.attribute_type" do
        attr = diagram.find_entity("RENTAL").attributes.first

        expect(attr.attribute_type).to eq("Map<K, V>")
      end
    end

    # Guards the O(n) fix for tilde_prefix/tilde_suffix (see grammar
    # comment). An absolute duration bound is too weak here -- at
    # 20,000 chars the reverted O(n^2) grammar was still fast enough to
    # pass a 0.35s bound most of the time (measured: 5/5 green reverting
    # tilde_suffix, 4/5 green reverting tilde_prefix). Asserting the
    # SCALING RATIO between a small and a 16x-larger run survives that:
    # see spec/support/er_tilde_timing.rb for the measured linear vs
    # quadratic ratios MAX_LINEAR_SCALING_RATIO sits between.
    it "parses a long non-tilde run before a tilde type at a linear rate",
       :speed do
      expect(tilde_parse_scaling_ratio(50_000, 800_000, position: :prefix))
        .to be < ErTildeTiming::MAX_LINEAR_SCALING_RATIO
    end

    # tilde_prefix and tilde_suffix are independent Parslet rules fixed
    # together; a mutant that reverts only tilde_suffix leaves the
    # prefix-only case above green, so this covers the suffix side with
    # the same scaling-ratio bound.
    it "parses a long non-tilde run after a tilde type at a linear rate",
       :speed do
      expect(tilde_parse_scaling_ratio(50_000, 800_000, position: :suffix))
        .to be < ErTildeTiming::MAX_LINEAR_SCALING_RATIO
    end

    # Guards the O(n) fix for `process_tilde_set` (`builders/er_diagram.rb`):
    # a Codex review found it re-scanned the WHOLE char array with
    # `index`/`rindex` after every pair replacement, quadratic in the
    # number of tildes in a single attribute type. A many-tilde-pair type
    # is a different input family than the long-single-run cases above --
    # this exercises the builder's pairing loop, not the grammar's atom.
    it "converts a type with many adjacent tilde pairs at a linear rate",
       :speed do
      expect(tilde_pair_count_scaling_ratio(1_000, 16_000))
        .to be < ErTildeTiming::MAX_LINEAR_SCALING_RATIO
    end

    # Guards the O(n) `note` grammar rule (`grammars/er_diagram.rb`): a
    # native `match('[^"]').repeat` folds one-char Slices back together
    # with `Slice#+`, quadratic in note length -- measured at 8.8GB RSS
    # and 0.42s CPU for a single 32,000-char note before the fix.
    it "parses a long quoted note at a linear rate", :speed do
      expect(note_parse_scaling_ratio(10_000, 160_000))
        .to be < ErTildeTiming::MAX_LINEAR_SCALING_RATIO
    end

    # A CHUNK-BOUNDARY regression: `tilde_marked_run` is matched
    # internally in bounded chunks (`DelimitedRun`, see the grammar
    # comment) -- a naive per-chunk anchored regex is only exact for a
    # pure character-class run, not this pattern's paired-delimiter
    # requirement, so a run straddling the chunk boundary used to
    # truncate instead of continuing into the next chunk (or raise
    # entirely, for a single run longer than one chunk). Compared
    # against the SAME whole-input regex mermaid's own lexer builds for
    # this token, not hand-derived.
    ["~#{'a' * 60_000}~", "~#{Array.new(4_000) { 'a' * 12 }.join('~')}~"]
      .each_with_index do |input, index|
        it "matches long tilde run #{index + 1} across the chunk boundary" do
          expected = tilde_lexer_regex.match(input)[0]
          parsed = tilde_grammar.tilde_marked_run.parse(input,
                                                        prefix: true).to_s
          expect(parsed).to eq(expected)
        end
      end

    describe "parses a full ER attribute type whose tilde run crosses " \
             "the internal chunk boundary" do
      let(:inner) do
        "a" * 60_000
      end

      let(:source) do
        <<~MERMAID
          erDiagram
          RENTAL {
            ~#{inner}~ name
          }
        MERMAID
      end

      let(:diagram) do
        parser.parse(source)
      end

      let(:attr) do
        diagram.find_entity("RENTAL").attributes.first
      end

      before do
        inner
        source
        diagram
        attr
      end

      it "preserves property 1" do
        expect(attr.name).to eq("name")
      end

      it "preserves property 2" do
        expect(attr.attribute_type).to eq("<#{inner}>")
      end
    end

    # Differential check against the SAME whole-input regex used above,
    # across random segment content, segment counts, and total lengths
    # clustered around the internal chunk boundary (plus a spread of
    # other sizes) -- proves the chunk-boundary fix generalises past the
    # two hand-picked counterexamples above.
    it "matches the whole-input reference regex across random inputs near " \
       "the chunk boundary" do
      samples = random_tilde_samples
      mismatches = tilde_mismatches(samples)
      message = "#{mismatches.size}/#{samples.size} cases mismatched: " \
                "#{mismatches.first(3)}"
      expect(mismatches).to eq([]), message
    end

    # Guards against the OTHER shape a fixed-size-chunk atom can regress
    # on: many SHORT runs, not one long one. `tilde_prefix` used to chunk
    # at a fixed 50_000-char ceiling regardless of the run's own length,
    # so every short attribute type still paid a ~50_000-char consume +
    # rewind -- linear in MAX_CHUNK per attribute, not in the attribute's
    # own length. An absolute bound is too tight on a loaded CI box; the
    # scaling ratio between a small and 8x-larger attribute count
    # survives that (see spec/support/er_tilde_timing.rb's reasoning).
    it "parses many short tilde-typed attributes at a linear rate, not one " \
       "per fixed chunk", :speed do
      small_parse = -> { parser.parse(many_tilde_attributes(500)) }
      large_parse = -> { parser.parse(many_tilde_attributes(4_000)) }
      small_time = min_call_time { cpu_time(&small_parse) }
      large_time = min_call_time { cpu_time(&large_parse) }

      expect(large_time / small_time).to be < ErTildeTiming::MAX_LINEAR_SCALING_RATIO
    end

    context "when parsing one-to-one cardinality" do
      let(:source) { "erDiagram\nCUSTOMER ||--|| ADDRESS" }
      let(:diagram) { parser.parse(source) }

      it "retains rel.cardinality_from" do
        rel = diagram.relationships.first

        expect(rel.cardinality_from).to eq("one")
      end

      it "retains rel.cardinality_to" do
        rel = diagram.relationships.first

        expect(rel.cardinality_to).to eq("one")
      end
    end

    context "when parsing zero-or-one cardinality" do
      let(:source) { "erDiagram\nCUSTOMER ||--}o ADDRESS" }
      let(:diagram) { parser.parse(source) }

      it "retains rel.cardinality_from" do
        rel = diagram.relationships.first

        expect(rel.cardinality_from).to eq("one")
      end

      it "retains rel.cardinality_to" do
        rel = diagram.relationships.first

        expect(rel.cardinality_to).to eq("zero_or_one")
      end
    end

    context "when parsing one-or-more cardinality" do
      let(:source) { "erDiagram\nCUSTOMER ||--{| ORDER" }
      let(:diagram) { parser.parse(source) }

      it "retains rel.cardinality_from" do
        rel = diagram.relationships.first

        expect(rel.cardinality_from).to eq("one")
      end

      it "retains rel.cardinality_to" do
        rel = diagram.relationships.first

        expect(rel.cardinality_to).to eq("one_or_more")
      end
    end

    # `}|`, `o|` and `|o` are real crow's-foot cardinality tokens the
    # grammar was missing entirely. Corpus case
    # unknown/yari2-dc83acff.mmd uses `}|..||`.
    context "when parsing one-or-more and zero-or-one cardinality tokens" do
      let(:source) { "erDiagram\nFILM_ACTOR }|..|| FILM : fk" }
      let(:diagram) { parser.parse(source) }

      it "retains rel.cardinality_from" do
        rel = diagram.relationships.first

        expect(rel.cardinality_from).to eq("one_or_more")
      end

      it "retains rel.cardinality_to" do
        rel = diagram.relationships.first

        expect(rel.cardinality_to).to eq("one")
      end
    end

    context "when parsing the o| and |o zero-or-one cardinality tokens" do
      let(:source) { "erDiagram\nCUSTOMER o|--|o ADDRESS" }
      let(:diagram) { parser.parse(source) }

      it "retains rel.cardinality_from" do
        rel = diagram.relationships.first

        expect(rel.cardinality_from).to eq("zero_or_one")
      end

      it "retains rel.cardinality_to" do
        rel = diagram.relationships.first

        expect(rel.cardinality_to).to eq("zero_or_one")
      end
    end

    it "parses relationship without label" do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to be_nil
    end

    context "when parsing multiple entities and relationships" do
      let(:source) do
        <<~MERMAID
          erDiagram
          CUSTOMER ||--o{ ORDER
          ORDER ||--|{ LINE_ITEM
          PRODUCT ||--o{ LINE_ITEM
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.relationships.length" do
        expect(diagram.relationships.length).to eq(3)
      end

      it "retains entity_ids" do
        entity_ids = diagram.entities.map(&:id).sort

        expect(entity_ids).to eq(%w[CUSTOMER LINE_ITEM ORDER PRODUCT])
      end
    end

    it "raises ParseError for invalid syntax" do
      source = "invalid syntax"
      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError,
      )
    end
  end

  describe "style classes" do
    it "carries the class assigned via ::: (A1)" do
      diagram = parser.parse("erDiagram\nCAR:::someclass")

      expect(diagram.find_entity("CAR").classes).to eq(%w[someclass])
    end

    it "carries multiple classes in source order (A2)" do
      diagram = parser.parse("erDiagram\nPERSON:::anotherclass,someclass")

      expect(diagram.find_entity("PERSON").classes)
        .to eq(%w[anotherclass someclass])
    end

    context "when records each classDef with its own style text (A3)" do
      let(:source) do
        <<~MERMAID
          erDiagram
          classDef someclass fill:#f96
          classDef anotherclass color:blue
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.class_defs" do
        expect(diagram.class_defs).to eq(
          "someclass" => "fill:#f96", "anotherclass" => "color:blue",
        )
      end
    end

    context "when keeps a class on an entity with an attribute block (A4)" do
      let(:source) { "erDiagram\nCAR:::x {\nstring make\n}" }
      let(:diagram) { parser.parse(source) }

      it "retains entity.classes" do
        entity = diagram.find_entity("CAR")

        expect(entity.classes).to eq(%w[x])
      end

      it "retains entity.attributes.map name" do
        entity = diagram.find_entity("CAR")

        expect(entity.attributes.map(&:name)).to eq(%w[make])
      end
    end

    it "keeps a class on an entity with an empty block (A5)" do
      # An empty block yields a nil :attributes capture. Routing on
      # :entity_id alone (not :entity_id && :attributes) is what keeps
      # this case from losing its class.
      diagram = parser.parse("erDiagram\nCAR:::x {\n}")

      expect(diagram.find_entity("CAR").classes).to eq(%w[x])
    end

    it "gives an unclassed entity an empty class list (A6)" do
      diagram = parser.parse("erDiagram\nCAR")

      expect(diagram.find_entity("CAR").classes).to eq([])
    end

    context "when keeps classes on both relationship ends (A7)" do
      let(:source) { "erDiagram\nA:::x ||--o{ B:::y : label" }
      let(:diagram) { parser.parse(source) }

      it "retains diagram.find_entity A .classes" do
        expect(diagram.find_entity("A").classes).to eq(%w[x])
      end

      it "retains diagram.find_entity B .classes" do
        expect(diagram.find_entity("B").classes).to eq(%w[y])
      end

      it "retains rel.cardinality_from" do
        rel = diagram.relationships.first

        expect(rel.cardinality_from).to eq("one")
      end

      it "retains rel.cardinality_to" do
        rel = diagram.relationships.first

        expect(rel.cardinality_to).to eq("zero_or_more")
      end
    end

    it "accepts a space after the comma (A8)" do
      diagram = parser.parse("erDiagram\nCAR:::a, b")

      expect(diagram.find_entity("CAR").classes).to eq(%w[a b])
    end

    it "lets one classDef name several classes (A11)" do
      diagram = parser.parse("erDiagram\nclassDef a, b fill:#f9f")

      expect(diagram.class_defs).to eq("a" => "fill:#f9f", "b" => "fill:#f9f")
    end

    context "when keeps a repeated assignment in source order, not " \
            "deduped (A12)" do
      let(:diagram) { parser.parse("erDiagram\nCAR:::a\nCAR:::a") }

      it "retains diagram.find_entity CAR .classes" do
        expect(diagram.find_entity("CAR").classes).to eq(%w[a a])
      end
    end

    it "adds rather than replaces on a second entity-path assignment (A13)" do
      source = "erDiagram\nCAR:::a\nCAR:::b {\nstring m\n}"
      diagram = parser.parse(source)

      expect(diagram.find_entity("CAR").classes).to eq(%w[a b])
    end

    it "adds rather than replaces on the relationship path too (A13b)" do
      source = "erDiagram\nCAR:::a\nCAR:::b ||--o{ X : r"
      diagram = parser.parse(source)

      expect(diagram.find_entity("CAR").classes).to eq(%w[a b])
    end

    it "does not include a trailing semicolon in the style text (A15)" do
      diagram = parser.parse("erDiagram\nclassDef x fill:#f96;")

      expect(diagram.class_defs).to eq("x" => "fill:#f96")
    end

    it "accumulates a repeated classDef for the same name (A16)" do
      # Verified against mermaid's own parser: two classDef statements for
      # one name both survive, in source order — not the last one alone.
      source = "erDiagram\nclassDef a fill:red\nclassDef a stroke:blue"
      diagram = parser.parse(source)

      expect(diagram.class_defs).to eq("a" => "fill:red,stroke:blue")
    end

    # These six all raise TODAY, so a whole-file revert leaves them green —
    # mutation-check.sh will say STAYED GREEN, correctly. Keep them anyway:
    # each is the set mermaid itself rejects (verified against its own
    # parser, see the plan's harness), and nothing else in this suite
    # notices if the grammar is ever widened past mermaid.
    ["CAR:::", "CAR::x", "CAR:::a,", "CAR:::1bad", "classDef x", "CAR:::--"]
      .each do |fragment|
        it "rejects #{fragment.inspect} as mermaid does (A14)" do
          source = "erDiagram\n#{fragment}"
          expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
        end
      end
  end
end
