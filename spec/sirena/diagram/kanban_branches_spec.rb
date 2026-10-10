# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Kanban do
  def card(id, assigned:, priority:, ticket:)
    Sirena::Diagram::KanbanCard.new(
      id: id, text: id, assigned: assigned, priority: priority, ticket: ticket,
    )
  end

  def populated_board
    column = Sirena::Diagram::KanbanColumn.new(id: "todo", title: "Todo")
    column.cards = [card("one", assigned: "Ana", priority: "high", ticket: "1"),
                    card("two", assigned: "Bo", priority: "low", ticket: "2")]
    described_class.new(columns: [column])
  end

  it "treats a missing column collection as an empty valid board" do
    expect(described_class.new(columns: nil)).to be_valid
  end

  it "queries cards by each metadata dimension" do
    board = populated_board
    evidence = [board.cards_by_assigned("Ana"), board.cards_by_priority("low"),
                board.cards_by_ticket("2")].map { |items| items.map(&:id) }
    expect(evidence).to eq([["one"], ["two"], ["two"]])
  end

  it "finds a column and returns nil for an unknown identifier" do
    board = populated_board

    expect([board.find_column("todo")&.title, board.find_column("done")])
      .to eq(["Todo", nil])
  end

  describe Sirena::Diagram::KanbanCard do
    it "compacts missing metadata and reports whether any remains" do
      empty = described_class.new(id: "one", text: "One")
      tagged = described_class.new(id: "two", text: "Two", priority: "high")
      expected = [{}, false, { priority: "high" }, true]

      expect([empty.metadata, empty.has_metadata?, tagged.metadata,
              tagged.has_metadata?]).to eq(expected)
    end
  end
end
