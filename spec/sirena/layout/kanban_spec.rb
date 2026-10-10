# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/kanban"

module KanbanLayoutSpecHelpers
  def kanban_column(id, title, cards)
    Sirena::Diagram::KanbanColumn.new(id: id, title: title).tap do |column|
      cards.each do |card_id, text|
        card = Sirena::Diagram::KanbanCard.new(id: card_id, text: text)
        column.add_card(card)
      end
    end
  end

  def kanban_board(columns)
    Sirena::Diagram::Kanban.new.tap do |diagram|
      columns.each do |id, title, cards|
        diagram.add_column(kanban_column(id, title, cards))
      end
    end
  end

  def card_height(graph, id)
    graph.cards.find { |card| card.id == id }.background.height
  end

  def card_height_delta(transform, changed_id, changed_text)
    columns = [["todo", "Todo", [
      ["plain", "Plain card"], [changed_id, changed_text]
    ]]]
    graph = transform.to_graph(kanban_board(columns))
    card_height(graph, changed_id) - card_height(graph, "plain")
  end

  def column_growth_deltas(transform)
    columns = [
      ["plain", "Todo", [["card1", "Card"]]],
      ["broken", "One\nTwo\nThree", [["card2", "Card"]]],
    ]
    graph = transform.to_graph(kanban_board(columns))
    [column_height_delta(graph), card_y_delta(graph)]
  end

  def column_height_delta(graph)
    heights = graph.columns.to_h do |column|
      [column.id, column.background.height]
    end
    heights["broken"] - heights["plain"]
  end

  def card_y_delta(graph)
    positions = graph.cards.to_h do |card|
      [card.column_id, card.background.y]
    end
    positions["broken"] - positions["plain"]
  end

  def empty_graph
    { columns: [], cards: [], width: 0, height: 0 }
  end
end

RSpec.describe Sirena::Layout::Kanban do
  include KanbanLayoutSpecHelpers

  let(:transform) { described_class.new }

  describe "#to_graph" do
    # Asserted through the public `#to_graph` output rather than the private
    # `calculate_card_height`: what matters is the height a card actually
    # gets positioned with. Card text kept well under
    # `Sirena::MarkdownText::CARD_TEXT_CHAR_BUDGET` (25 visible
    # characters) — this test is about per-break growth, not truncation; a
    # fixture crossing the budget belongs to the spec below instead.
    it "grows a card's height by one EXTRA_LINE_HEIGHT per embedded " \
       "hard break" do
      delta = card_height_delta(transform, "broken", "One\nTwo\nThree")
      expect(delta).to eq(2 * described_class::EXTRA_LINE_HEIGHT)
    end

    # A card whose text wraps gets one EXTRA_LINE_HEIGHT per wrapped line,
    # and the full text is kept (no truncation).
    it "grows a card's height by one EXTRA_LINE_HEIGHT per wrapped line" do
      delta = card_height_delta(
        transform, "wrapped", "Create Blog about the new diagram"
      )
      expect(delta).to eq(described_class::EXTRA_LINE_HEIGHT)
    end

    # Round 3 Codex High: a multi-line column title (the same `count("\n")`
    # signal as card text above, applied to `column.title` instead) grew
    # nothing — `calculate_column_height` and `position_cards`'s starting
    # y-offset both used the flat `COLUMN_HEADER_HEIGHT` constant, so a
    # taller rendered header overflowed its own background rect and the
    # column's first card overlapped it.
    #
    # Mutation-check: delete the `column.title.to_s.count("\n") *
    # EXTRA_LINE_HEIGHT` term from `calculate_header_height`. Watched red:
    # both columns come back at the same height and their first cards at the
    # same starting y.
    it "grows a column's height and its first card's y by one " \
       "EXTRA_LINE_HEIGHT per embedded hard break in the title" do
      expected = Array.new(2, 2 * described_class::EXTRA_LINE_HEIGHT)
      expect(column_growth_deltas(transform)).to eq(expected)
    end
  end

  describe "#build_graph" do
    it "lays out empty shared data IR like the private model" do
      diagram = Sirena::Diagram::Kanban.new
      data = Sirena::Notation::Mermaid::IRAdapters::Kanban.call(diagram)

      expect(transform.call(data)).to eq(transform.call(diagram))
    end

    it "treats nil columns the same as empty columns, matching " \
       "Diagram::Kanban#valid?" do
      diagram = Sirena::Diagram::Kanban.new
      diagram.columns = nil
      actual = [diagram.valid?, transform.build_graph(diagram)]
      expect(actual).to eq([true, empty_graph])
    end

    it "returns an empty graph for an empty (bare-header) board" do
      diagram = Sirena::Diagram::Kanban.new

      expect(transform.build_graph(diagram)).to eq(empty_graph)
    end
  end
end
