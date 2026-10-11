# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Kanban do
  subject(:scene) { described_class.new.call(board) }

  let(:board) do
    Sirena::Diagram::Kanban.new.tap { |diagram| diagram.add_column(column) }
  end

  let(:column) do
    Sirena::Diagram::KanbanColumn.new(id: "todo", title: "Todo").tap do |item|
      item.add_card(card("owned", assigned: "Alice"))
      item.add_card(card("plain"))
    end
  end

  def card(id, **metadata)
    Sirena::Diagram::KanbanCard.new({ id: id, text: id, **metadata })
  end

  it "keeps one card's metadata off its sibling" do
    evidence = scene.cards.to_h { |item| [item.id, item.metadata.map(&:text)] }
    expect(evidence).to eq("owned" => ["Assigned:", "Alice"], "plain" => [])
  end
end
