# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::ErDiagram do
  include ErTildeTiming

  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses simple ER diagram with relationship' do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"
      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::ErDiagram)
      expect(diagram.entities.length).to eq(2)
      expect(diagram.relationships.length).to eq(1)
    end

    it 'parses non-identifying relationship' do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.from_id).to eq('CUSTOMER')
      expect(rel.to_id).to eq('ORDER')
      expect(rel.relationship_type).to eq('non-identifying')
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('zero_or_more')
    end

    it 'parses identifying relationship' do
      source = "erDiagram\nCUSTOMER ||==o{ ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.relationship_type).to eq('identifying')
    end

    it 'parses entity with attributes' do
      source = <<~MERMAID
        erDiagram
        CUSTOMER {
          int id PK
          string name
          string email FK
        }
      MERMAID
      diagram = parser.parse(source)

      entity = diagram.find_entity('CUSTOMER')
      expect(entity).not_to be_nil
      expect(entity.attributes.length).to eq(3)

      attr1 = entity.attributes[0]
      expect(attr1.name).to eq('id')
      expect(attr1.attribute_type).to eq('int')
      expect(attr1.key_type).to eq('PK')

      attr2 = entity.attributes[1]
      expect(attr2.name).to eq('name')
      expect(attr2.attribute_type).to eq('string')
      expect(attr2.key_type).to be_nil

      attr3 = entity.attributes[2]
      expect(attr3.name).to eq('email')
      expect(attr3.attribute_type).to eq('string')
      expect(attr3.key_type).to eq('FK')
    end

    # A type name that isn't a bare identifier -- mermaid accepts a
    # `~...~`-quoted one. Corpus case unknown/079_platform_yari2_78.mmd.
    it 'parses an attribute with a tilde-quoted multi-word type' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          ~timestamp with time zone~ rental_date "NN"
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.name).to eq('rental_date')
      expect(attr.attribute_type).to eq('<timestamp with time zone>')
    end

    # A quoted note after the key type -- mermaid renders it as the
    # attribute's comment (its own `attribute-comment` SVG column,
    # verified against spec/mermaid/unknown/079_platform_yari2_78.svg). It
    # must reach the model, not just be consumed and dropped by the
    # grammar -- the renderer spec proves it reaches the rendered SVG too.
    it 'carries the quoted note after the key type into the model' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          int rental_id PK "NN"
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.name).to eq('rental_id')
      expect(attr.key_type).to eq('PK')
      expect(attr.note).to eq('NN')
    end

    # An empty quoted note, `""`, comes back from Parslet's
    # `.repeat.as(:string)` as `[]`, not an empty Parslet::Slice --
    # `extract_text` special-cases that (`builders/er_diagram.rb`). Without
    # the guard, `[].to_s` ships the literal text "[]" as the note instead
    # of an empty string.
    it 'carries an empty quoted note as an empty string, not the literal "[]"' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          int rental_id PK ""
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.note).to eq('')
    end

    # Mermaid's ER `COMMENT` token accepts only double-quoted text with no
    # embedded quote and no backslash escape -- a Codex review found the
    # note rule reused the shared `string`/`single_quoted_string` grammar
    # (`common.rb`), which accepts BOTH, wrongly parsing text mermaid
    # 11.16.1 rejects outright.
    it 'refuses a single-quoted note the way mermaid does' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          int rental_id PK 'NN'
        }
      MERMAID

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it 'refuses a note with a backslash-escaped quote the way mermaid does' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          int rental_id PK "a\\"b"
        }
      MERMAID

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    # `RunPattern` (the atom `tilde_prefix`/`tilde_suffix`/`tilde_marked_run`
    # are built from, grammars/er_diagram.rb) must find the matched run's
    # length in CHARACTERS, not bytes -- `StringScanner#match?` (what
    # `Source#matches?` delegates to) reports bytes, while `Source#consume`
    # advances by characters. A byte count fed to `consume` over-consumes on
    # any multibyte character: a Codex review at this tip found
    # `foo~bar baz~<CJK char> field` came back with type
    # `"foo<bar baz><CJK char> f"` and name `"ield"` -- the multibyte
    # suffix char (3 bytes, 1 character) pulled 2 extra ASCII characters
    # into the type.
    it 'does not over-consume past a multibyte character in the tilde suffix' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          foo~bar baz~中 field
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.attribute_type).to eq('foo<bar baz>中')
      expect(attr.name).to eq('field')
    end

    # Same byte/character bug, prefix side: a multibyte character before
    # the opening tilde must count as one character, not several bytes.
    it 'does not over-consume past a multibyte character in the tilde prefix' do
      grammar = Sirena::Parser::Grammars::ErDiagram.new

      expect(grammar.tilde_type.parse('é~foo~')[:string].to_s).to eq('é~foo~')
    end

    # A `Parslet::Slice` built without a line cache raises `ArgumentError`
    # from `#line_and_column` instead of returning a position -- a Codex
    # review at this tip found `RunPattern`'s hand-built `Slice` omitted it.
    it 'keeps a captured tilde type slice able to report its line and column' do
      grammar = Sirena::Parser::Grammars::ErDiagram.new

      result = grammar.tilde_type.parse('~foo~')

      expect(result[:string].line_and_column).to eq([1, 1])
    end

    # Verified against mermaid 11.16.1's lexer regex for this token --
    # `/^(?:([^\s]*)[~].*[~]([^\s]*))/i`, no `/s` flag -- `.` cannot cross
    # a newline in a JS regex without that flag, so mermaid never treats
    # this as one tilde-quoted type spanning the break. Sirena's grammar
    # must refuse it too, not silently accept a newline inside the tildes.
    it 'refuses a tilde-quoted type only when it spans a newline' do
      single_line = <<~MERMAID
        erDiagram
        RENTAL {
          ~timestamp with time zone~ rental_date
        }
      MERMAID
      # Proves the refusal below is specific to the newline, not tilde
      # support being absent -- without this, the raise_error expectation
      # passes for the wrong reason on code that never parses tildes at all.
      expect { parser.parse(single_line) }.not_to raise_error

      multi_line = <<~MERMAID
        erDiagram
        RENTAL {
          ~timestamp
        with time zone~ rental_date
        }
      MERMAID

      expect { parser.parse(multi_line) }.to raise_error(Sirena::Parser::ParseError)
    end

    # JS `\s` (what `[^\s]*` excludes) is ECMA-262 WhiteSpace, not just
    # space/tab/newline -- it includes U+00A0 (NBSP) and the other
    # Unicode space separators. `tilde_suffix` must stop there too, not
    # swallow an NBSP as if it were an ordinary character. Tested at the
    # grammar rule directly: a full diagram parse would also need `ws`/
    # `space` (inherited from `Grammars::Common`, out of this fix's
    # scope) to treat NBSP as a token separator, which is a separate gap.
    it 'stops the tilde suffix at an NBSP, matching JS `\s`' do
      grammar = Sirena::Parser::Grammars::ErDiagram.new

      expect(grammar.tilde_suffix.parse('foo').to_s).to eq('foo')
      expect { grammar.tilde_suffix.parse("foo bar") }
        .to raise_error(Parslet::ParseFailed, /Don't know what to do with/)
    end

    # JS's `.` refuses to cross ANY ECMA-262 LineTerminator, not only
    # `\n` -- CR and the Unicode line/paragraph separators (U+2028,
    # U+2029) too. A bare CR inside the tildes must refuse exactly like
    # the `\n` case above, not be silently swallowed as an ordinary char.
    it 'refuses a tilde-quoted type that spans a bare CR' do
      source = "erDiagram\nRENTAL {\n  ~foo\rbar~ name\n}\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    # Mermaid's lexer regex has no minimum length between the two tildes
    # (`.*`, not `.+`), so `~~` alone matches as an empty type -- verified
    # by running that regex directly (node) against mermaid's own compiled
    # erDiagram lexer. Sirena's grammar previously required `repeat(1)`,
    # which refused a diagram mermaid renders fine.
    it 'accepts an empty tilde-quoted type' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          ~~ rental_date
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.name).to eq('rental_date')
      # `~~` has two tildes, so mermaid's own `parseGenericTypes` still
      # pairs them into `<>` rather than deleting them -- it is not a
      # special case for emptiness, just the general first/last-tilde
      # pairing applied to a zero-length middle.
      expect(attr.attribute_type).to eq('<>')
    end

    # Mermaid's lexer captures a non-whitespace run directly before the
    # opening tilde and after the closing one, not just `~...~` alone --
    # `foo~bar baz~qux` parses in mermaid as the single type
    # `foo~bar baz~qux`, verified by running mermaid's own erDiagram
    # parser. Codex round-2 finding 1 (ffaabf5d).
    it 'keeps a non-whitespace prefix and suffix around a tilde-quoted type' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          foo~bar baz~qux rental_date
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.name).to eq('rental_date')
      expect(attr.attribute_type).to eq('foo<bar baz>qux')
    end

    # Codex round-2 finding: the greedy inner match (`.*` in mermaid's
    # lexer) lands on the LAST tilde on the line, not the first, so a
    # type with two embedded pairs -- `~bar~baz qux~` and
    # `foo~one~two three~four~five` -- is ONE token, not split at the
    # first closing tilde.
    it 'greedily matches to the last tilde on the line, not the first' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          ~bar~baz qux~ name
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.name).to eq('name')
      # 3 tildes (odd): the leading one is unpaired and stays literal,
      # per mermaid's own `parseGenericTypes` (`~test~T~` -> `~test<T>`).
      expect(attr.attribute_type).to eq('~bar<baz qux>')
    end

    it 'greedily spans multiple embedded tilde pairs across spaces' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          foo~one~two three~four~five name
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.name).to eq('name')
      # 4 tildes pair from the outside in: the outermost pair (1st/4th)
      # wraps the whole middle, the inner pair (2nd/3rd) nests inside it.
      expect(attr.attribute_type).to eq('foo<one<two three>four>five')
    end

    # A comma inside a generic's tildes (`Map~K, V~`) splits the type text
    # into three parts before `process_tilde_set` ever runs, so
    # `should_combine_tilde_sets?` must rejoin them. Expected value taken
    # by running mermaid's own `parseGenericTypes` (packages/mermaid/src/
    # diagrams/common/common.ts, verified against the compiled function in
    # node_modules/mermaid/dist/mermaid.js) on the identical input, not
    # hand-derived.
    it 'rejoins a comma inside a single tilde-quoted generic type' do
      source = <<~MERMAID
        erDiagram
        RENTAL {
          Map~K, V~ rental_date
        }
      MERMAID
      diagram = parser.parse(source)

      attr = diagram.find_entity('RENTAL').attributes.first
      expect(attr.name).to eq('rental_date')
      expect(attr.attribute_type).to eq('Map<K, V>')
    end

    # Guards the O(n) fix for tilde_prefix/tilde_suffix (see grammar
    # comment). An absolute duration bound is too weak here -- at
    # 20,000 chars the reverted O(n^2) grammar was still fast enough to
    # pass a 0.35s bound most of the time (measured: 5/5 green reverting
    # tilde_suffix, 4/5 green reverting tilde_prefix). Asserting the
    # SCALING RATIO between a small and a 16x-larger run survives that:
    # see spec/support/er_tilde_timing.rb for the measured linear vs
    # quadratic ratios MAX_LINEAR_SCALING_RATIO sits between.
    it 'parses a long non-tilde run before a tilde type at a linear rate' do
      expect(tilde_parse_scaling_ratio(5_000, 80_000, position: :prefix))
        .to be < ErTildeTiming::MAX_LINEAR_SCALING_RATIO
    end

    # tilde_prefix and tilde_suffix are independent Parslet rules fixed
    # together; a mutant that reverts only tilde_suffix leaves the
    # prefix-only case above green, so this covers the suffix side with
    # the same scaling-ratio bound.
    it 'parses a long non-tilde run after a tilde type at a linear rate' do
      expect(tilde_parse_scaling_ratio(5_000, 80_000, position: :suffix))
        .to be < ErTildeTiming::MAX_LINEAR_SCALING_RATIO
    end

    # Guards the O(n) fix for `process_tilde_set` (`builders/er_diagram.rb`):
    # a Codex review found it re-scanned the WHOLE char array with
    # `index`/`rindex` after every pair replacement, quadratic in the
    # number of tildes in a single attribute type. A many-tilde-pair type
    # is a different input family than the long-single-run cases above --
    # this exercises the builder's pairing loop, not the grammar's atom.
    it 'converts a type with many adjacent tilde pairs at a linear rate' do
      expect(tilde_pair_count_scaling_ratio(1_000, 16_000))
        .to be < ErTildeTiming::MAX_LINEAR_SCALING_RATIO
    end

    it 'parses one-to-one cardinality' do
      source = "erDiagram\nCUSTOMER ||--|| ADDRESS"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('one')
    end

    it 'parses zero-or-one cardinality' do
      source = "erDiagram\nCUSTOMER ||--}o ADDRESS"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('zero_or_one')
    end

    it 'parses one-or-more cardinality' do
      source = "erDiagram\nCUSTOMER ||--{| ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('one_or_more')
    end

    # `}|`, `o|` and `|o` are real crow's-foot cardinality tokens the
    # grammar was missing entirely. Corpus case
    # unknown/079_platform_yari2_78.mmd uses `}|..||`.
    it 'parses one-or-more and zero-or-one cardinality tokens' do
      source = "erDiagram\nFILM_ACTOR }|..|| FILM : fk"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('one_or_more')
      expect(rel.cardinality_to).to eq('one')
    end

    it 'parses the o| and |o zero-or-one cardinality tokens' do
      source = "erDiagram\nCUSTOMER o|--|o ADDRESS"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.cardinality_from).to eq('zero_or_one')
      expect(rel.cardinality_to).to eq('zero_or_one')
    end

    it 'parses relationship without label' do
      source = "erDiagram\nCUSTOMER ||--o{ ORDER"
      diagram = parser.parse(source)

      rel = diagram.relationships.first
      expect(rel.label).to be_nil
    end

    it 'parses multiple entities and relationships' do
      source = <<~MERMAID
        erDiagram
        CUSTOMER ||--o{ ORDER
        ORDER ||--|{ LINE_ITEM
        PRODUCT ||--o{ LINE_ITEM
      MERMAID
      diagram = parser.parse(source)

      expect(diagram.relationships.length).to eq(3)
      # Should have 4 unique entities
      entity_ids = diagram.entities.map(&:id).sort
      expect(entity_ids).to eq(%w[CUSTOMER LINE_ITEM ORDER PRODUCT])
    end

    it 'raises ParseError for invalid syntax' do
      source = 'invalid syntax'
      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      )
    end
  end

  describe 'style classes' do
    it 'carries the class assigned via ::: (A1)' do
      diagram = parser.parse("erDiagram\nCAR:::someclass")

      expect(diagram.find_entity('CAR').classes).to eq(%w[someclass])
    end

    it 'carries multiple classes in source order (A2)' do
      diagram = parser.parse("erDiagram\nPERSON:::anotherclass,someclass")

      expect(diagram.find_entity('PERSON').classes)
        .to eq(%w[anotherclass someclass])
    end

    it 'records each classDef with its own style text (A3)' do
      source = <<~MERMAID
        erDiagram
        classDef someclass fill:#f96
        classDef anotherclass color:blue
      MERMAID
      diagram = parser.parse(source)

      expect(diagram.class_defs).to eq(
        'someclass' => 'fill:#f96', 'anotherclass' => 'color:blue'
      )
    end

    it 'keeps a class on an entity with an attribute block (A4)' do
      source = "erDiagram\nCAR:::x {\nstring make\n}"
      diagram = parser.parse(source)
      entity = diagram.find_entity('CAR')

      expect(entity.classes).to eq(%w[x])
      expect(entity.attributes.map(&:name)).to eq(%w[make])
    end

    it 'keeps a class on an entity with an empty block (A5)' do
      # An empty block yields a nil :attributes capture. Routing on
      # :entity_id alone (not :entity_id && :attributes) is what keeps
      # this case from losing its class.
      diagram = parser.parse("erDiagram\nCAR:::x {\n}")

      expect(diagram.find_entity('CAR').classes).to eq(%w[x])
    end

    it 'gives an unclassed entity an empty class list (A6)' do
      diagram = parser.parse("erDiagram\nCAR")

      expect(diagram.find_entity('CAR').classes).to eq([])
    end

    it 'keeps classes on both relationship ends (A7)' do
      # Each end captures under a DIFFERENT name (:from_classes,
      # :to_classes). Giving both the same name would drop the from-end
      # class silently when Parslet merges the statement hash.
      source = "erDiagram\nA:::x ||--o{ B:::y : label"
      diagram = parser.parse(source)
      rel = diagram.relationships.first

      expect(diagram.find_entity('A').classes).to eq(%w[x])
      expect(diagram.find_entity('B').classes).to eq(%w[y])
      expect(rel.cardinality_from).to eq('one')
      expect(rel.cardinality_to).to eq('zero_or_more')
    end

    it 'accepts a space after the comma (A8)' do
      diagram = parser.parse("erDiagram\nCAR:::a, b")

      expect(diagram.find_entity('CAR').classes).to eq(%w[a b])
    end

    it 'lets one classDef name several classes (A11)' do
      diagram = parser.parse("erDiagram\nclassDef a, b fill:#f9f")

      expect(diagram.class_defs).to eq('a' => 'fill:#f9f', 'b' => 'fill:#f9f')
    end

    it 'keeps a repeated assignment in source order, not deduped (A12)' do
      # Verified against mermaid's own db: cssClasses is "default a a" for
      # this source, not "default a" — a repeat is NOT collapsed. Whether
      # that matters is a rendering question (a later duplicate can win a
      # conflict); the parser's job is only to keep what was written.
      diagram = parser.parse("erDiagram\nCAR:::a\nCAR:::a")

      expect(diagram.find_entity('CAR').classes).to eq(%w[a a])
    end

    it 'adds rather than replaces on a second entity-path assignment (A13)' do
      source = "erDiagram\nCAR:::a\nCAR:::b {\nstring m\n}"
      diagram = parser.parse(source)

      expect(diagram.find_entity('CAR').classes).to eq(%w[a b])
    end

    it 'adds rather than replaces on the relationship path too (A13b)' do
      source = "erDiagram\nCAR:::a\nCAR:::b ||--o{ X : r"
      diagram = parser.parse(source)

      expect(diagram.find_entity('CAR').classes).to eq(%w[a b])
    end

    it 'does not include a trailing semicolon in the style text (A15)' do
      diagram = parser.parse("erDiagram\nclassDef x fill:#f96;")

      expect(diagram.class_defs).to eq('x' => 'fill:#f96')
    end

    it 'accumulates a repeated classDef for the same name (A16)' do
      # Verified against mermaid's own parser: two classDef statements for
      # one name both survive, in source order — not the last one alone.
      source = "erDiagram\nclassDef a fill:red\nclassDef a stroke:blue"
      diagram = parser.parse(source)

      expect(diagram.class_defs).to eq('a' => 'fill:red,stroke:blue')
    end

    # These six all raise TODAY, so a whole-file revert leaves them green —
    # mutation-check.sh will say STAYED GREEN, correctly. Keep them anyway:
    # each is the set mermaid itself rejects (verified against its own
    # parser, see the plan's harness), and nothing else in this suite
    # notices if the grammar is ever widened past mermaid.
    it 'rejects what mermaid rejects (A14)' do
      fragments = [
        'CAR:::',
        'CAR::x',
        'CAR:::a,',
        'CAR:::1bad',
        'classDef x',
        'CAR:::--'
      ]

      fragments.each do |fragment|
        source = "erDiagram\n#{fragment}"

        expect { parser.parse(source) }.to raise_error(
          Sirena::Parser::ParseError
        )
      end
    end
  end
end
