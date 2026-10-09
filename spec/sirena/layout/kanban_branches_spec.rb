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

  def stacked_columns
    diagram.add_column(column("todo", "Todo", [card("a", "A"), card("b", "B")]))
    diagram.add_column(column("done", "Done", [card("c", "C")]))
  end

  def two_empty_columns
    diagram.add_column(column("todo", "Todo"))
    diagram.add_column(column("done", "Done"))
  end

  describe "positioning branches" do
    it "spaces multiple columns horizontally and bounds the board" do
      two_empty_columns

      expect(
        [graph.width, graph.height, graph.columns.map { |item| item.background.x },
         graph.cards],
      ).to eq([540.0, 140.0, [40.0, 300.0], []])
    end

    it "uses only header and padding height for an empty column" do
      single_todo_column

      item = graph.columns.first
      expect(
        [item.background.width, item.background.height, item.header.height,
         item.badge, item.badge_label],
      ).to eq([200.0, 60.0, 50.0, nil, nil])
    end

    it "grows a card and column for rendered lines and metadata rows" do
      rich_card_column

      expect(
        [graph.width, graph.height, graph.columns.first.background.height,
         graph.cards.first.background.height, graph.cards.first.metadata.length],
      ).to eq([280.0, 284.0, 204.0, 134.0, 4])
    end

    it "puts every framed board element in final canvas coordinates" do
      rich_card_column
      item = graph.columns.first
      work = graph.cards.first

      expect(
        [graph.width, graph.height, graph.view_box,
         [item.background.x, item.background.y],
         [item.header.x, item.header.y], [item.title.x, item.title.y],
         [item.badge.x, item.badge.y],
         [item.badge_label.x, item.badge_label.y],
         [work.background.x, work.background.y],
         [work.label.x, work.label.y],
         work.metadata.map { |label| [label.x, label.y] }],
      ).to eq(
        [280.0, 284.0, "0 0 280 284.0", [40.0, 40.0], [40.0, 40.0],
         [140.0, 70.0], [215.0, 55.0], [225.0, 69.0], [50.0, 100.0],
         [60.0, 125.0], [[60.0, 168.0], [120.0, 168.0],
                         [60.0, 186.0], [120.0, 186.0]]],
      )
    end

    it "expands text-dependent geometry for a larger theme" do
      rich_card_column
      contrast = described_class.new.call(
        diagram, theme: Sirena::Theme::Registry.get(:high_contrast)
      )

      expect(contrast.cards.first.label.font_size).to eq(16.0)
      expect(contrast.cards.first.background.height)
        .to be > graph.cards.first.background.height
      expect(contrast.height).to be > graph.height
    end

    it "stacks cards with vertical spacing and keeps the tallest bound" do
      stacked_columns

      expect(
        [graph.width, graph.height,
         graph.columns.map { |item| item.background.height },
         graph.cards.map { |item| item.background.y }],
      ).to eq([540.0, 325.0, [245.0, 150.0], [100.0, 195.0, 100.0]])
    end
  end
end
