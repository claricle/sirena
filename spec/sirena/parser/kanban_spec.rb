# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::KanbanParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    context 'with a simple kanban board' do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              docs[Create Documentation]
        MERMAID
      end

      it 'parses successfully' do
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Kanban)
      end

      it 'creates the correct column' do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(1)
        expect(diagram.columns.first.id).to eq('id1')
        expect(diagram.columns.first.title).to eq('Todo')
      end

      it 'creates the correct card' do
        diagram = parser.parse(source)
        column = diagram.columns.first
        expect(column.cards.size).to eq(1)
        expect(column.cards.first.id).to eq('docs')
        expect(column.cards.first.text).to eq('Create Documentation')
      end
    end

    context 'with multiple columns and cards' do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              docs[Create Documentation]
              blog[Create Blog]
            id2[In Progress]
              feature[Implement Feature]
            id3[Done]
              release[Release v1.0]
        MERMAID
      end

      it 'creates all columns' do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(3)
        expect(diagram.columns.map(&:title)).to eq(['Todo', 'In Progress', 'Done'])
      end

      it 'creates all cards in correct columns' do
        diagram = parser.parse(source)
        expect(diagram.columns[0].cards.size).to eq(2)
        expect(diagram.columns[1].cards.size).to eq(1)
        expect(diagram.columns[2].cards.size).to eq(1)
      end
    end

    context 'with card metadata' do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              docs[Create Documentation]@{ priority: 'High', ticket: 'MC-1001' }
        MERMAID
      end

      it 'parses metadata correctly' do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.priority).to eq('High')
        expect(card.ticket).to eq('MC-1001')
      end
    end

    context 'with assigned metadata' do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              feature[Implement Feature]@{ assigned: 'dev1' }
        MERMAID
      end

      it 'parses assigned field' do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.assigned).to eq('dev1')
      end
    end

    context 'with icon metadata' do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              task[Fix bugs]@{ icon: 'star' }
        MERMAID
      end

      it 'parses icon field' do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.icon).to eq('star')
      end
    end

    context 'with label metadata' do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              task[Task]@{ label: 'urgent' }
        MERMAID
      end

      it 'parses label field' do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.label).to eq('urgent')
      end
    end

    context 'with multiple metadata fields' do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              task[Task]@{ priority: 'High', assigned: 'dev1', ticket: 'MC-100' }
        MERMAID
      end

      it 'parses all metadata fields' do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.priority).to eq('High')
        expect(card.assigned).to eq('dev1')
        expect(card.ticket).to eq('MC-100')
      end
    end

    context 'with empty columns' do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
            id2[Done]
        MERMAID
      end

      it 'creates columns without cards' do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(2)
        expect(diagram.columns[0].cards.size).to eq(0)
        expect(diagram.columns[1].cards.size).to eq(0)
      end
    end

    context 'with invalid syntax' do
      let(:source) { 'invalid kanban syntax' }

      it 'raises a parse error' do
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    # --- bucket 1: the node label is optional -------------------------------
    # Every context below is named for the mermaid-js corpus cases it pins,
    # under spec/mermaid/kanban/.

    context 'with a bare node (corpus 015, 034)' do
      let(:source) { "kanban\n    root\n" }

      it 'creates one column whose title falls back to its id' do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(1)
        expect(diagram.columns.first.id).to eq('root')
        expect(diagram.columns.first.title).to eq('root')
      end
    end

    context 'with a bare hierarchy (corpus 016)' do
      let(:source) { "kanban\n    root\n      child1\n      child2\n" }

      it 'nests bare children as cards titled by their ids' do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(['root'])
        cards = diagram.columns.first.cards
        expect(cards.map(&:id)).to eq(%w[child1 child2])
        expect(cards.map(&:text)).to eq(%w[child1 child2])
      end
    end

    context 'with metadata on a bare top-level node' do
      # Five corpus cases over four distinct payloads (036 and 037 share
      # one); each becomes a single column titled by its id.
      {
        '035' => 'assigned: knsv',
        '036/037' => 'icon: star',
        '039' => 'icon: star, assigned: knsv',
        '041' => 'ticket: MC-1234'
      }.each do |corpus_id, payload|
        it "titles the column by its id (corpus #{corpus_id})" do
          diagram = parser.parse("kanban\n        root@{ #{payload} }\n")
          aggregate_failures do
            expect(diagram.columns.size).to eq(1), "corpus #{corpus_id}"
            expect(diagram.columns.first.title).to eq('root'), "corpus #{corpus_id}"
          end
        end
      end
    end

    context 'with a label: override on a bare column (corpus 040)' do
      let(:source) { "kanban\n        root@{ icon: star, label: 'fix things' }\n" }

      it 'prefers the label metadata over the id' do
        diagram = parser.parse(source)
        expect(diagram.columns.first.title).to eq('fix things')
      end
    end

    context 'with constructs at the bare node boundary' do
      # Two directions on purpose: the accept half dies if the bare
      # alternative is removed, the refuse half dies if it is widened past an
      # identifier. Round shapes are covered below (corpus 017, 022, 023,
      # 031); directives (::icon, :::class) belong to a later bucket and
      # must keep failing rather than being swallowed as literal labels.
      it 'accepts a bare identifier' do
        expect(parser.parse("kanban\n  root\n").columns.map(&:id)).to eq(['root'])
      end

      it 'still refuses a class directive' do
        expect { parser.parse("kanban\n  root\n  :::hot\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'still refuses trailing free text after a bare id' do
        # The reason bare_item stays an identifier: mermaid accepts a bare
        # label with spaces, and widening to match would swallow the
        # unsupported constructs above as literal labels.
        aggregate_failures do
          ['root trailing', 'root two more words'].each do |line|
            expect { parser.parse("kanban\n  #{line}\n") }
              .to raise_error(Sirena::Parser::ParseError), line
          end
        end
      end
    end

    context 'with a round shape and no id (corpus 017)' do
      let(:source) { "kanban\n    (root)\n" }

      it 'auto-assigns an id and titles the column from the shape text' do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(1)
        expect(diagram.columns.first.id).to eq('kanban-1')
        expect(diagram.columns.first.title).to eq('root')
      end

      it 'assigns the next id deterministically for a second unlabelled shape' do
        diagram = parser.parse("kanban\n  (Col A)\n  (Col B)\n")
        expect(diagram.columns.map(&:id)).to eq(%w[kanban-1 kanban-2])
        expect(diagram.columns.map(&:title)).to eq(['Col A', 'Col B'])
      end
    end

    context 'with an id and a round shape on a child (corpus 022, 023)' do
      # 022 indents the root; 023 does not. Indentation of the root line
      # never decides which items become columns - only the MINIMUM
      # indentation among all items does - so both parse identically.
      {
        '022' => "kanban\n    root\n      theId(child1)\n",
        '023' => "kanban\nroot\n      theId(child1)\n"
      }.each do |corpus_id, source|
        it "accepts the shaped child (corpus #{corpus_id})" do
          diagram = parser.parse(source)
          aggregate_failures do
            expect(diagram.columns.map(&:id)).to eq(['root']), corpus_id
            card = diagram.columns.first.cards.first
            expect(card.id).to eq('theId'), corpus_id
            expect(card.text).to eq('child1'), corpus_id
          end
        end
      end
    end

    context 'with a quoted label on a round-shaped item' do
      # Not from the corpus - a Codex-constructed input. `shaped_item` and
      # `unlabelled_shaped_item` captured a quoted body as literal
      # characters, quotes included, and ended the shape at the first
      # unquoted `)` - so a label containing one broke the parse entirely.
      # Mirrors mindmap.rb's `square_shape`, the existing precedent for
      # quoted content inside a bracketed shape: the quotes are stripped,
      # and a quoted body may contain the shape's own delimiter.
      it 'strips the quotes from an id-prefixed round shape' do
        diagram = parser.parse("kanban\n  col(\"Hello\")\n")
        expect(diagram.columns.first.title).to eq('Hello')
      end

      it 'strips the quotes from an unlabelled round shape' do
        diagram = parser.parse("kanban\n  (\"Task\")\n")
        expect(diagram.columns.first.title).to eq('Task')
      end

      it 'keeps a paren inside a quoted id-prefixed label' do
        diagram = parser.parse("kanban\n  col(\"Todo (urgent)\")\n")
        expect(diagram.columns.first.title).to eq('Todo (urgent)')
      end

      it 'keeps a paren inside a quoted unlabelled label' do
        diagram = parser.parse("kanban\n  (\"Fix (today)\")\n")
        expect(diagram.columns.first.title).to eq('Fix (today)')
      end

      it 'parses a column and a child both carrying a quoted label' do
        diagram = parser.parse("kanban\n  col(\"Hello\")\n    (\"Task\")\n")
        column = diagram.columns.first
        expect(column.title).to eq('Hello')
        expect(column.cards.first.text).to eq('Task')
      end

      it 'parses a paren inside quotes on both the column and its child, where the unquoted form failed to parse at all' do
        diagram = parser.parse("kanban\n  col(\"Todo (urgent)\")\n    (\"Fix (today)\")\n")
        column = diagram.columns.first
        expect(column.title).to eq('Todo (urgent)')
        expect(column.cards.first.text).to eq('Fix (today)')
      end
    end

    context 'with a malformed quoted label on a round-shaped item' do
      # Not from the corpus - a Codex-constructed input. When the quoted
      # alternative in `round_text` failed - an empty body, or no closing
      # quote at all - the plain alternative silently accepted the leading
      # `"` as an ordinary character, so `col("")` rendered the literal
      # text `""` instead of failing. Mermaid rejects both inputs
      # (`Expecting 'NODE_DESCR', got 'NODE_DEND'`), so Sirena must too.
      it 'refuses an empty quoted body rather than rendering literal quotes' do
        expect { parser.parse("kanban\n  col(\"\")\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'refuses an unterminated quoted body rather than keeping the leading quote' do
        expect { parser.parse("kanban\n  col(\"unterminated)\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    context 'with a markdown-string body on a round-shaped item' do
      # Not from the corpus - a Codex-constructed input. A quoted body that
      # itself opens and closes with a backtick - `"`text`"` - is mermaid's
      # markdown-string syntax: it strips the backtick pair and renders the
      # content through markdown (measured against mmdc 11.12.0: `col("`Hi
      # **urgent**`")` draws `Hi <strong>urgent</strong>`). Sirena has no
      # markdown renderer anywhere in the codebase, so the former behaviour
      # - matching this as an ordinary quoted body - kept the backticks as
      # literal text and drew `` `Hi **urgent**` `` instead. Refused
      # explicitly now, the same way the malformed bodies above are, rather
      # than silently drawing something mermaid does not.
      it 'refuses a backtick-wrapped quoted body on an id-prefixed shape' do
        expect { parser.parse("kanban\n  col(\"`Hello`\")\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'refuses a backtick-wrapped quoted body on an unlabelled shape' do
        expect { parser.parse("kanban\n  (\"`Hello`\")\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'refuses an empty backtick-wrapped body the same way mermaid does' do
        expect { parser.parse("kanban\n  col(\"``\")\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'keeps an ordinary quoted body that merely contains a backtick pair' do
        diagram = parser.parse("kanban\n  col(\"Hello `code` world\")\n")
        expect(diagram.columns.first.title).to eq('Hello `code` world')
      end

      # A body with a single, unmatched backtick - `"`Hello"` with no
      # closing backtick before the quote - is not the markdown-string
      # shape above, so this fix leaves it alone: it stays a literal quoted
      # body, matching the sibling malformed-body pin two contexts up.
      # mmdc 11.12.0 actually lexer-errors on this one too ("Unrecognized
      # text"), a pre-existing gap this High does not cover - it is about
      # the closed backtick pair, not a lone backtick.
      it 'keeps a quoted body that opens with a backtick but never closes one' do
        diagram = parser.parse("kanban\n  col(\"`Hello\")\n")
        expect(diagram.columns.first.title).to eq('`Hello')
      end
    end

    context 'with a shape-delimiter character in an unquoted round-shaped label' do
      # Not from the corpus - a Codex-constructed input. `round_text`'s
      # unquoted alternative excluded only `)`, the shape's own closer, so
      # it accepted `(`, `]` and `}` too - mermaid's lexer treats all
      # three as node-shape delimiters even unquoted and rejects them
      # (measured against mmdc 11.12.0). `[` and `{` are not delimiters to
      # mermaid there, so they stay accepted on both sides.
      ['(', ']', '}'].each do |delimiter|
        it "refuses an unquoted label carrying a literal #{delimiter.inspect}" do
          expect { parser.parse("kanban\n  col(a#{delimiter}b)\n") }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end

      ['[', '{'].each do |literal|
        it "keeps an unquoted label carrying a literal #{literal.inspect}" do
          diagram = parser.parse("kanban\n  col(a#{literal}b)\n")
          expect(diagram.columns.first.title).to eq("a#{literal}b")
        end
      end
    end

    context 'with round-shaped items and a blank row together (corpus 031)' do
      let(:source) do
        "kanban\n  root(Root)\n    Child(Child)\n      a(a)\n\n      b[New Stuff]\n"
      end

      it 'keeps every card across the blank row' do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(['root'])
        column = diagram.columns.first
        expect(column.title).to eq('Root')
        expect(column.cards.map(&:id)).to eq(%w[Child a b])
        expect(column.cards.map(&:text)).to eq(['Child', 'a', 'New Stuff'])
      end
    end

    # corpus 012, 013 and 014 are byte-identical (20 bytes, same md5), so
    # this pins one input that three corpus entries happen to share.
    context 'with blank and spaces-only rows (corpus 012 = 013 = 014)' do
      let(:source) { "kanban\nroot\n A\n \n\n B\n" }

      it 'ignores the empty rows and keeps the bare nodes' do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(['root'])
        expect(diagram.columns.first.cards.map(&:id)).to eq(%w[A B])
      end
    end

    context 'with a node three levels deep (corpus 018)' do
      let(:source) { "kanban\n    root\n      child1\n        leaf1\n      child2\n" }

      it 'flattens every deeper level into the column card list' do
        # Mermaid does not distinguish deeper levels here, and neither does
        # the builder: anything past the minimum indent is a card.
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(['root'])
        expect(diagram.columns.first.cards.map(&:id)).to eq(%w[child1 leaf1 child2])
      end
    end

    context 'with several bare sections (corpus 019)' do
      let(:source) { "kanban\n    section1\n    section2\n" }

      it 'creates a column per section and no cards' do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(%w[section1 section2])
        expect(diagram.columns.map { |c| c.cards.size }).to eq([0, 0])
      end
    end

    context 'with bare and labelled columns together (corpus 002)' do
      let(:source) do
        # The corpus source verbatim: the same card id `docs` appears under
        # both columns, which is the shape this case exists to cover.
        "kanban\n  id1[Todo]\n    docs[Create Documentation]\n  " \
        "id2\n    docs[Create Blog about the new diagram]\n"
      end

      it 'accepts both forms on one board' do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(%w[id1 id2])
        expect(diagram.columns.map(&:title)).to eq(['Todo', 'id2'])
      end

      it 'keeps a repeated card id in its own column' do
        diagram = parser.parse(source)
        expect(diagram.columns.map { |c| c.cards.map(&:id) }).to eq([['docs'], ['docs']])
      end
    end

    context 'with identical bare cards in one column' do
      # Bare cards make three look-alike lines trivial to write, and the
      # builder must keep one card per line. The corpus 002 example above
      # cannot cover it, because its two `docs` cards carry different text.
      it 'keeps one card per line rather than collapsing look-alikes' do
        diagram = parser.parse("kanban\n  col\n    a\n    a\n    a\n")
        expect(diagram.columns.first.cards.map(&:id)).to eq(%w[a a a])
      end
    end

    context 'with a real root in the wrong place (corpus 020)' do
      # KNOWN GAP, pinned deliberately. mmdc 11.12.0 REJECTS this input with
      # "Items without section detected, found section (\"fakeRoot\")".
      # Sirena accepts it and drops the two nodes that precede the first
      # column, because the builder picks a global minimum indent and only
      # classifies during finalize. Refusing it needs indentation-validity
      # checking, a different construct from an optional label, so it is
      # deferred to a later bucket. This example exists so the
      # over-acceptance cannot drift unnoticed, and it should go red when
      # that bucket lands.
      let(:source) { "kanban\n          root\n        fakeRoot\n    realRootWrongPlace\n" }

      it 'over-accepts, keeping only the shallowest node' do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(['realRootWrongPlace'])
        expect(diagram.columns.first.cards).to be_empty
      end
    end

    context 'with a label: override on a labelled column' do
      # Metadata beats bracket text, which is what mmdc renders for
      # `root[L]@{ label: xx }`. No corpus case covers the labelled shape -
      # 040 is bare - so it is pinned here.
      let(:source) { "kanban\n  id1[Todo]@{ label: 'Renamed' }\n" }

      it 'prefers the label metadata over the bracket text' do
        expect(parser.parse(source).columns.first.title).to eq('Renamed')
      end
    end

    context 'with an empty label:' do
      # An empty label is not a label. mmdc renders the bracket text for
      # `id1[Todo]@{ label: '' }`, and the id when there is no bracket text.
      it 'falls back to the bracket text' do
        diagram = parser.parse("kanban\n  id1[Todo]@{ label: '' }\n")
        expect(diagram.columns.first.title).to eq('Todo')
      end

      it 'falls back to the id when there is no bracket text' do
        diagram = parser.parse("kanban\n  id1@{ label: '' }\n")
        expect(diagram.columns.first.title).to eq('id1')
      end

      it 'treats a double-quoted empty label the same way' do
        diagram = parser.parse(%(kanban\n  id1[Todo]@{ label: "" }\n))
        expect(diagram.columns.first.title).to eq('Todo')
      end

      # Whitespace is not empty, so this one does NOT fall back - it is the
      # single case that separates `.empty?` from `.strip.empty?`, and
      # stripping here would be wrong. Oracle-confirmed rather than
      # incidental: mmdc 11.12.0 emits `<span class="nodeLabel"></span>` -
      # empty, with no text node at all - where a kept label gives
      # `<p>x</p>` and a fallback gives the bracket text. So the label is
      # consumed rather than fallen back to; it just leaves nothing behind.
      it 'keeps a whitespace-only label rather than falling back' do
        diagram = parser.parse("kanban\n  id1[Todo]@{ label: '   ' }\n")
        expect(diagram.columns.first.title).to eq('   ')
      end
    end

    context 'with metadata keys that collide with a card field' do
      # Mermaid ignores `id:`/`text:` as metadata; they are the card's own
      # fields. No corpus case uses them. The collision was already reachable
      # on base through a labelled card, which has always taken metadata -
      # the bare form only adds a second route to it. Reachable either way,
      # so neither route may emit wrong output.
      it 'does not let text: overwrite the card text' do
        diagram = parser.parse("kanban\n  col[C]\n    card[K]@{ text: 'CLOB' }\n")
        expect(diagram.columns.first.cards.first.text).to eq('K')
      end

      it 'does not let id: overwrite the card id' do
        diagram = parser.parse("kanban\n  col[C]\n    card@{ id: 'CLOB' }\n")
        card = diagram.columns.first.cards.first
        expect(card.id).to eq('card')
        expect(card.text).to eq('card')
      end
    end

    context 'with metadata on a bare card' do
      # The intersection of this bucket's two changes: a card with no bracket
      # label, carrying metadata.
      let(:source) { "kanban\n  col[Todo]\n    child1@{ assigned: knsv }\n" }

      it 'titles the card by its id and keeps the metadata' do
        card = parser.parse(source).columns.first.cards.first
        expect(card.id).to eq('child1')
        expect(card.text).to eq('child1')
        expect(card.assigned).to eq('knsv')
      end
    end

    context 'with the header token used as a node name' do
      # mmdc reserves `kanban` as a node name and refuses it in any case,
      # bare or labelled, as a column or a card. Only the whole word is
      # taken. No other keyword is reserved - measured against mmdc 11.12.0.
      it 'refuses a bare kanban column' do
        expect { parser.parse("kanban\n  root[Root]\n  kanban\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'refuses a bare kanban card' do
        expect { parser.parse("kanban\n  root[Root]\n    kanban\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'refuses it whatever the case' do
        aggregate_failures do
          %w[Kanban KANBAN KaNbAn kAnBaN kanBan kanbaN].each do |word|
            expect { parser.parse("kanban\n  root[Root]\n  #{word}\n") }
              .to raise_error(Sirena::Parser::ParseError), word
          end
        end
      end

      it 'refuses it even with a bracket label' do
        expect { parser.parse("kanban\n  root[Root]\n  kanban[Label]\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'accepts an id that merely contains the word' do
        # `kanban_x` is the case that matters: `_` is inside the boundary
        # class, so it continues the word rather than ending it. mermaid's
        # own `\b` agrees - it accepts `kanban_x` and rejects `kanban-x`.
        diagram = parser.parse(
          "kanban\n  root[Root]\n  kanbanBoard\n  mykanban\n  kanban_x\n"
        )
        expect(diagram.columns.map(&:title))
          .to eq(%w[Root kanbanBoard mykanban kanban_x])
      end

      it 'reserves no other keyword' do
        # The single home of this list; the grammar comment points here.
        # Every token was probed against mmdc and parses as an ordinary node.
        others = %w[graph section title class classDef click style subgraph
                    accTitle accDescr end flowchart]
        body = others.map { |word| "  #{word}\n" }.join
        diagram = parser.parse("kanban\n  root[Root]\n#{body}")
        expect(diagram.columns.map(&:title)).to eq(['Root'] + others)
      end
    end

    context 'with a metadata value mermaid resolves as falsy' do
      # mermaid gates each field on JS truthiness after js-yaml resolves the
      # scalar, so these are never set and the field falls back. Every value
      # below was driven through mmdc 11.12.0, not recalled.
      def title_for(value)
        parser.parse("kanban\n  id1[A]@{ label: #{value} }\n").columns.first.title
      end

      it 'falls back for every spelling of zero' do
        # The signed forms carry the leading-sign branch of each radix
        # pattern, and `0e-0` the exponent's - the only sign the float
        # reaches, since `unquoted_value` admits `-` but not `+`.
        aggregate_failures do
          %w[0 -0 00 000 -00 0x0 0o0 0b0 0e0 0E0
             -0x0 -0o0 -0b0 0e-0].each do |zero|
            expect(title_for(zero)).to eq('A'), "expected #{zero} to be dropped"
          end
        end
      end

      it 'falls back for false and null in the three casings js-yaml resolves' do
        # lowercase, Capitalised and UPPERCASE - and no others.
        aggregate_failures do
          %w[false False FALSE null Null NULL].each do |word|
            expect(title_for(word)).to eq('A'), "expected #{word} to be dropped"
          end
        end
      end

      it 'keeps other mixed-case spellings, which stay strings' do
        aggregate_failures do
          %w[fAlSe nUll].each do |word|
            expect(title_for(word)).to eq(word), "expected #{word} to be kept"
          end
        end
      end

      it 'keeps an uppercase radix prefix, which js-yaml leaves as a string' do
        # All three prefixes are lowercase-only, so `0x0`/`0o0`/`0b0` are
        # zero while these stay strings. The exponent marker is the one
        # case-insensitive spelling, covered by `0E0` above.
        aggregate_failures do
          %w[0X0 0O0 0B0].each do |kept|
            expect(title_for(kept)).to eq(kept), "expected #{kept} to be kept"
          end
        end
      end

      it 'keeps truthy scalars and quoted falsy-looking ones' do
        expect(title_for('1')).to eq('1')
        expect(title_for('true')).to eq('true')
        expect(title_for("'0'")).to eq('0')
        expect(title_for('"false"')).to eq('false')
      end

      it 'reads the values a dot, plus or tilde makes' do
        # These three characters are new in the unquoted charset. Before
        # them the whole line raised a parse error, where mmdc 11.12.0 draws
        # the node. js-yaml resolves the first five falsy, so the title
        # falls back, and keeps the rest as numbers.
        aggregate_failures do
          %w[0.0 -0.0 +0 .nan ~].each do |zero|
            expect(title_for(zero)).to eq('A'), "expected #{zero} to be dropped"
          end
          %w[1.5 0.1 +7].each do |kept|
            expect(title_for(kept)).to eq(kept), "expected #{kept} to be kept"
          end
        end
      end

      it 'drops zero written with digit separators, including after a prefix' do
        # js-yaml honours `_` between digits, and `_` is in the unquoted
        # charset, so these reach here. A run of any length counts, and
        # `0x_0` shows one directly after a radix prefix.
        aggregate_failures do
          %w[0_0 0__0 0___0 0_0_0 00__00 -0_0 0x_0 0x0_0 0b0_0 0o0_0].each do |zero|
            expect(title_for(zero)).to eq('A'), "expected #{zero} to be dropped"
          end
        end
      end

      it 'strips the separators before converting, so a non-zero payload survives' do
        # The other half of the separator rule, and the only half that can
        # tell stripping from tolerating. Every value in the drop example
        # above has a ZERO payload, where Ruby's own `to_i` already reaches
        # zero whether or not the separators are removed first - `0x_0` and
        # `0__0` are dropped either way. Only a NON-zero payload behind a
        # separator distinguishes them: without the strip, `to_i(16)` reads
        # `0x_1` as 0 and `to_i` truncates `0__1` at the double separator,
        # and both would be dropped where mermaid draws a label.
        #
        # mmdc 11.12.0 resolves each of these to a truthy number and keeps
        # the label row - `0x_1` to 1, `0x_a` to 10, `0x_10` to 16, `-0x_1`
        # to -1. Sirena keeps the raw text, the pre-existing divergence
        # noted above.
        aggregate_failures do
          %w[0__1 0___1 -0__1 00__01 0__10
             0x_1 0x__1 0x_10 0x_a -0x_1 0x_0_1
             0o_1 0o__1 0o_10 -0o_1 0o_0_1
             0b_1 0b__1 0b_10 -0b_1 0b_0_1
             0__1e0 0__1E0].each do |kept|
            expect(title_for(kept)).to eq(kept), "expected #{kept} to be kept"
          end
        end
      end

      it 'keeps a separator that is not between digits' do
        # The boundary that makes this a rule rather than "delete every
        # underscore": leading, trailing, bridging a prefix, or standing
        # alone - mermaid keeps every one of these as a string.
        aggregate_failures do
          %w[_0 0_ __0 0_0_ -_0 _ 0_x0 _0e0].each do |kept|
            expect(title_for(kept)).to eq(kept), "expected #{kept} to be kept"
          end
        end
      end

      it 'honours a separator anywhere in the mantissa, trailing edge included' do
        # The float pattern is `[0-9][0-9_]*`, so a mantissa may even END in
        # separators - unlike the int pattern, where `0_` stays a string.
        aggregate_failures do
          %w[0_0e0 0_e0 0__e0 -0_e0 0_E0 0_0_e0].each do |zero|
            expect(title_for(zero)).to eq('A'), "expected #{zero} to be dropped"
          end
        end
      end

      it 'ignores a separator inside the exponent' do
        # `_0e0` is not here: a leading separator is its own rule, covered by
        # the not-between-digits example above.
        aggregate_failures do
          %w[0e0_0 0e_0 0_e_0].each do |kept|
            expect(title_for(kept)).to eq(kept), "expected #{kept} to be kept"
          end
        end
      end

      it 'keeps an integer that ends in a separator' do
        # Guards the int and float branches against being unified: widening
        # the float mantissa must not leak into the decimal case. Nothing is
        # refused here - the value survives verbatim as the title.
        aggregate_failures do
          expect(title_for('0_')).to eq('0_')
          expect(title_for('0_0_')).to eq('0_0_')
        end
      end

      it 'drops a falsy value on each of the five gated fields, and keeps a truthy one' do
        # The positive control matters: KanbanCard#metadata is a `.compact`
        # over five attributes, so an empty hash cannot by itself tell
        # "dropped" from "never parsed". The truthy row proves the fields do
        # land when mermaid would set them.
        falsy = "kanban\n  col[C]\n    k[K]@{ assigned: 0, ticket: false, " \
                "icon: null, priority: 0x0, label: '' }\n"
        truthy = "kanban\n  col[C]\n    k[K]@{ assigned: knsv, ticket: MC-1, " \
                 "icon: star, priority: High, label: 'Fix' }\n"

        aggregate_failures do
          card = parser.parse(falsy).columns.first.cards.first
          expect(card.metadata).to eq({})
          expect(card.text).to eq('K')

          kept = parser.parse(truthy).columns.first.cards.first
          expect(kept.metadata).to eq(assigned: 'knsv', ticket: 'MC-1',
                                      icon: 'star', priority: 'High', label: 'Fix')
        end
      end
    end
  end
end
