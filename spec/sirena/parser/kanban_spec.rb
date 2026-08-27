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

    context 'with metadata on a bare top-level node (corpus 035, 041)' do
      let(:source) { "kanban\n        root@{ assigned: knsv, ticket: MC-1234 }\n" }

      it 'creates a column titled by its id' do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(1)
        expect(diagram.columns.first.title).to eq('root')
      end

      it 'drops assigned and ticket, which a column cannot carry' do
        # KanbanColumn has only id/title/cards. Pinned so a later model
        # change cannot silently alter it.
        column = parser.parse(source).columns.first
        expect(column).not_to respond_to(:assigned)
        expect(column).not_to respond_to(:ticket)
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
    end

    context 'with blank and spaces-only rows (corpus 012, 013, 014)' do
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
        "kanban\n  id1[Todo]\n    docs[Create Documentation]\n  id2\n    blog[Create Blog]\n"
      end

      it 'accepts both forms on one board' do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(%w[id1 id2])
        expect(diagram.columns.map(&:title)).to eq(['Todo', 'id2'])
      end
    end

    context 'with multi-key metadata on a bare column (corpus 036, 037, 039)' do
      let(:source) { "kanban\n        root@{ icon: star, assigned: knsv }\n" }

      it 'parses every key and still titles the column by its id' do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(1)
        expect(diagram.columns.first.title).to eq('root')
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
  end
end
