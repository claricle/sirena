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

  describe "positioning branches" do
    it "spaces multiple columns horizontally and sizes the board to their bounds" do
      diagram.add_column(column("todo", "Todo"))
      diagram.add_column(column("done", "Done"))

      expect(graph).to match(
        columns: [hash_including(x: 0), hash_including(x: 260)],
        cards: [], width: 460, height: 60
      )
    end

    it "uses only header and padding height for an empty column" do
      diagram.add_column(column("todo", "Todo"))

      expect(graph[:columns].first).to include(
        width: 200, height: 60, header_height: 50, card_count: 0,
      )
    end

    it "grows a card and column for rendered lines and metadata rows" do
      work = card("work", "One\nTwo", assigned: "Alice", priority: "High")
      diagram.add_column(column("todo", "Todo", [work]))

      expect(graph).to match(
        columns: [hash_including(height: 204)],
        cards: [hash_including(height: 134, has_metadata: true)],
        width: 200, height: 204
      )
    end

    it "stacks cards with vertical spacing and keeps the tallest column bound" do
      first_column = column("todo", "Todo", [card("a", "A"), card("b", "B")])
      diagram.add_column(first_column)
      diagram.add_column(column("done", "Done", [card("c", "C")]))

      expect(graph).to match(
        columns: [hash_including(height: 245), hash_including(height: 150)],
        cards: [hash_including(y: 60), hash_including(y: 155), hash_including(y: 60)],
        width: 460, height: 245
      )
    end
  end
end
