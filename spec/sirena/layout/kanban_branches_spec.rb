# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Kanban do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Kanban.new }

  def card(id, text, **metadata)
    Sirena::Diagram::KanbanCard.new({ id: id, text: text, **metadata })
  end

  def column(id, title, cards = [])
    Sirena::Diagram::KanbanColumn.new(id: id, title: title).tap do |item|
      cards.each { |entry| item.add_card(entry) }
    end
  end

  def single_todo_column
    diagram.add_column(column("todo", "Todo"))
  end

  def rich_card_column
    work = card("work", "One\nTwo", assigned: "Alice", priority: "High")
    diagram.add_column(column("todo", "Todo", [work]))
  end

  def rich_card_layout
    {
      columns: [hash_including(height: 204)],
      cards: [hash_including(height: 134, has_metadata: true)],
      width: 200, height: 204
    }
  end

  def stacked_columns
    diagram.add_column(column("todo", "Todo", [card("a", "A"), card("b", "B")]))
    diagram.add_column(column("done", "Done", [card("c", "C")]))
  end

  def two_empty_columns
    diagram.add_column(column("todo", "Todo"))
    diagram.add_column(column("done", "Done"))
  end

  def stacked_layout
    {
      columns: [hash_including(height: 245), hash_including(height: 150)],
      cards: [hash_including(y: 60), hash_including(y: 155),
              hash_including(y: 60)],
      width: 460, height: 245
    }
  end

  describe "positioning branches" do
    it "spaces multiple columns horizontally and bounds the board" do
      two_empty_columns

      expect(graph).to match(
        columns: [hash_including(x: 0), hash_including(x: 260)],
        cards: [], width: 460, height: 60
      )
    end

    it "uses only header and padding height for an empty column" do
      single_todo_column

      expect(graph[:columns].first).to include(
        width: 200, height: 60, header_height: 50, card_count: 0,
      )
    end

    it "grows a card and column for rendered lines and metadata rows" do
      rich_card_column

      expect(graph).to match(rich_card_layout)
    end

    it "stacks cards with vertical spacing and keeps the tallest bound" do
      stacked_columns

      expect(graph).to match(stacked_layout)
    end
  end
end
