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
      # Four corpus cases that differ only in the metadata payload; each
      # becomes a single column titled by its id.
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

    context 'with metadata a column has no attribute for' do
      # This pins a MODEL SHAPE, not transform behaviour, and the name says
      # so deliberately. `assigned` cannot reach a column no matter what the
      # transform does, because build_column reads only id/title/cards - so
      # no transform change can redden this. What it does catch is the model
      # growing an attribute later, which would silently change what a bare
      # column carries. Five corpus cases (035, 036, 037, 039, 041) reach a
      # column through this path.
      let(:source) { "kanban\n        root@{ assigned: knsv }\n" }

      it 'defines no attribute the metadata could land in' do
        expect(Sirena::Diagram::KanbanColumn.attributes.keys)
          .to contain_exactly(:id, :title, :cards)
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
      # identifier. Round shapes and directives belong to later buckets and
      # must keep failing rather than being swallowed as literal labels.
      it 'accepts a bare identifier' do
        expect(parser.parse("kanban\n  root\n").columns.map(&:id)).to eq(['root'])
      end

      it 'still refuses a round-bracket shape' do
        expect { parser.parse("kanban\n  root(Root)\n") }
          .to raise_error(Sirena::Parser::ParseError)
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
          ['root some words', 'root trailing', 'card some words'].each do |line|
            expect { parser.parse("kanban\n  #{line}\n") }
              .to raise_error(Sirena::Parser::ParseError), line
          end
        end
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
      # incidental: mmdc keeps the whitespace label and emits a text node for
      # it, so the blank look is HTML whitespace collapsing, not a fallback
      # to the bracket text.
      it 'keeps a whitespace-only label rather than falling back' do
        diagram = parser.parse("kanban\n  id1[Todo]@{ label: '   ' }\n")
        expect(diagram.columns.first.title).to eq('   ')
      end
    end

    context 'with metadata keys that collide with a card field' do
      # Mermaid ignores `id:`/`text:` as metadata; they are the card's own
      # fields. No corpus case uses them, but the bare form made this input
      # reachable, so it must not emit wrong output.
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
        %w[Kanban KANBAN KaNbAn kAnBaN kanBan kanbaN].each do |word|
          expect { parser.parse("kanban\n  root[Root]\n  #{word}\n") }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end

      it 'refuses it even with a bracket label' do
        expect { parser.parse("kanban\n  root[Root]\n  kanban[Label]\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'accepts an id that merely contains the word' do
        diagram = parser.parse("kanban\n  root[Root]\n  kanbanBoard\n  mykanban\n")
        expect(diagram.columns.map(&:title)).to eq(%w[Root kanbanBoard mykanban])
      end

      it 'reserves no other keyword' do
        # Every token probed against mmdc; all parse as ordinary nodes.
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
        %w[0 -0 00 000 -00 0x0 0o0 0b0 0e0 0E0].each do |zero|
          expect(title_for(zero)).to eq('A'), "expected #{zero} to be dropped"
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
          %w[fAlSe nUll FaLsE NuLl].each do |word|
            expect(title_for(word)).to eq(word), "expected #{word} to be kept"
          end
        end
      end

      it 'keeps 0X0, which js-yaml leaves as a string' do
        # The hex prefix is lowercase-only, so `0x0` is zero but `0X0` is not.
        expect(title_for('0X0')).to eq('0X0')
      end

      it 'keeps truthy scalars and quoted falsy-looking ones' do
        expect(title_for('1')).to eq('1')
        expect(title_for('true')).to eq('true')
        expect(title_for("'0'")).to eq('0')
        expect(title_for('"false"')).to eq('false')
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
