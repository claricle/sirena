# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/kanban"

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
    cards = [card("a", "A"), card("b", "B")]
    diagram.add_column(column("todo", "Todo", cards))
    diagram.add_column(column("done", "Done", [card("c", "C")]))
  end

  def two_empty_columns
    diagram.add_column(column("todo", "Todo"))
    diagram.add_column(column("done", "Done"))
  end

  describe "positioning branches" do
    context "with multiple columns" do
      subject(:board_geometry) do
        [graph.width, graph.height,
         graph.columns.map { |item| item.background.x }, graph.cards]
      end

      it "spaces them horizontally and bounds the board" do
        two_empty_columns

        expect(board_geometry).to eq([485.0, 115.0, [40.0, 245.0], []])
      end
    end

    context "with an empty column" do
      subject(:column_geometry) do
        item = graph.columns.first
        [item.background.width, item.background.height, item.header.height,
         item.badge, item.badge_label]
      end

      it "uses only header and padding height" do
        single_todo_column

        expect(column_geometry).to eq([200.0, 35.0, 25.0, nil, nil])
      end
    end

    context "with a rich card" do
      subject(:rich_card_geometry) do
        [graph.width, graph.height, graph.columns.first.background.height,
         graph.cards.first.background.height, graph.cards.first.metadata.length]
      end

      it "grows the card and column for rendered lines and metadata rows" do
        rich_card_column

        expect(rich_card_geometry).to eq([280.0, 219.0, 139.0, 104.0, 4])
      end

      it "lays out shared data IR identically to the private model" do
        rich_card_column
        data = Sirena::Notation::Mermaid::IRAdapters::Kanban.call(diagram)

        expect(described_class.new.call(data)).to eq(graph)
      end
    end

    context "with a framed board" do
      subject(:framed_board_evidence) do
        item = graph.columns.first
        work = graph.cards.first
        actual = [graph.width, graph.height, graph.view_box,
                  [item.background.x, item.background.y],
                  [item.header.x, item.header.y], [item.title.x, item.title.y],
                  [item.badge.x, item.badge.y],
                  [item.badge_label.x, item.badge_label.y],
                  [work.background.x, work.background.y],
                  [work.label.x, work.label.y],
                  work.metadata.map { |label| [label.x, label.y] }]
        expected = [280.0, 219.0, "0 0 280 219.0",
                    [40.0, 40.0], [40.0, 40.0], [140.0, 57.5],
                    [215.0, 42.5], [225.0, 56.5], [47.5, 65.0],
                    [57.5, 90.0],
                    [[57.5, 139.0], [117.5, 139.0],
                     [57.5, 157.0], [117.5, 157.0]]]

        [actual, expected]
      end

      it "puts every element in final canvas coordinates" do
        rich_card_column

        expect(framed_board_evidence.first).to eq(framed_board_evidence.last)
      end
    end

    context "with a larger theme" do
      subject(:theme_geometry) do
        contrast = described_class.new.call(
          diagram, theme: Sirena::Theme::Registry.get(:high_contrast)
        )
        [contrast.cards.first.label.font_size,
         contrast.cards.first.background.height >
           graph.cards.first.background.height,
         contrast.height > graph.height]
      end

      it "expands text-dependent geometry" do
        rich_card_column

        expect(theme_geometry).to eq([16.0, true, true])
      end
    end

    context "with stacked cards" do
      subject(:stacked_geometry) do
        [graph.width, graph.height,
         graph.columns.map { |item| item.background.height },
         graph.cards.map { |item| item.background.y }]
      end

      it "uses vertical spacing and keeps the tallest bound" do
        stacked_columns

        expect(stacked_geometry).to eq(
          [485.0, 208.0, [128.0, 79.0], [65.0, 114.0, 65.0]],
        )
      end
    end
  end
end
