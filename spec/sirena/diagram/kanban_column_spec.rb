# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::KanbanColumn do
  describe ".attributes" do
    # A bare column carries only what the parser can give it: metadata a
    # column has no attribute for is dropped, and `label:` becomes the
    # title. `icon` and `classes` now DO land on a column, but from
    # different sources: `icon` from `@{ icon: ... }` metadata on the
    # column's own item line (see the 'with metadata on a bare top-level
    # node' parser context) OR a standalone `::icon(...)` line right after
    # it; `classes` ONLY from a standalone `:::className` directive line -
    # mermaid does not read a `classes` key out of `@{ ... }` metadata at
    # all (Builders::Kanban::BoardBuilder#apply_modifier / #parse_metadata).
    # This catches the model growing a further attribute later, which would
    # silently change what a bare column holds.
    it "defines exactly the attributes a column metadata entry can land in" do
      expect(described_class.attributes.keys)
        .to contain_exactly(:id, :title, :icon, :classes, :cards)
    end
  end

  describe Sirena::Diagram::KanbanCard do
    subject(:card) { described_class.new(id: "card", text: "Do the work") }

    it "is valid with an identifier and text" do
      expect(card.valid?).to be(true)
    end

    it "is invalid with a nil identifier" do
      card.id = nil
      expect(card.valid?).to be(false)
    end

    it "is invalid with an empty identifier" do
      card.id = ""
      expect(card.valid?).to be(false)
    end

    it "is invalid with nil text" do
      card.text = nil
      expect(card.valid?).to be(false)
    end

    it "is invalid with empty text" do
      card.text = ""
      expect(card.valid?).to be(false)
    end
  end

  describe Sirena::Diagram::KanbanColumn do
    subject(:column) { described_class.new(id: "todo", title: "Todo") }

    it "is valid with an identifier and title" do
      expect(column.valid?).to be(true)
    end

    it "is invalid with a nil identifier" do
      column.id = nil
      expect(column.valid?).to be(false)
    end

    it "is invalid with an empty identifier" do
      column.id = ""
      expect(column.valid?).to be(false)
    end

    it "is invalid with a nil title" do
      column.title = nil
      expect(column.valid?).to be(false)
    end

    it "is invalid with an empty title" do
      column.title = ""
      expect(column.valid?).to be(false)
    end

    it "is invalid when a child card is invalid" do
      column.add_card(Sirena::Diagram::KanbanCard.new(id: "card", text: ""))
      expect(column.valid?).to be(false)
    end
  end

  describe Sirena::Diagram::Kanban do
    subject(:board) { described_class.new }

    it "is valid when empty" do
      expect(board.valid?).to be(true)
    end

    it "is invalid when a column is invalid" do
      board.add_column(Sirena::Diagram::KanbanColumn.new(id: "", title: "Todo"))
      expect(board.valid?).to be(false)
    end

    it "is valid when every column is valid" do
      column = Sirena::Diagram::KanbanColumn.new(id: "todo", title: "Todo")
      board.add_column(column)
      expect(board.valid?).to be(true)
    end
  end
end
