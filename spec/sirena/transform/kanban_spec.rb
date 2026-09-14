# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Transform::Kanban do
  let(:transform) { described_class.new }

  describe '#to_graph' do
    # Round 2 of the markdown-labels feature grew `calculate_card_height`
    # for a hard line break embedded in card text (from a markdown newline,
    # rendered as an extra `<tspan>` line by
    # Renderer::MarkdownText#parse_lines) — this had no spec anywhere.
    #
    # Asserted through the public `#to_graph` output rather than the
    # private `calculate_card_height`: what matters is the height a card
    # actually gets positioned with.
    #
    # Mutation-check: delete the `card.text.to_s.count("\n") *
    # EXTRA_LINE_HEIGHT` term from `calculate_card_height`. Watched red:
    # both cards come back at the same height.
    it "grows a card's height by one EXTRA_LINE_HEIGHT per embedded hard break" do
      diagram = Sirena::Diagram::Kanban.new.tap do |d|
        d.add_column(Sirena::Diagram::KanbanColumn.new(id: 'todo', title: 'Todo').tap do |column|
          column.add_card(Sirena::Diagram::KanbanCard.new(id: 'plain', text: 'Plain card'))
          column.add_card(Sirena::Diagram::KanbanCard.new(id: 'broken', text: "Line one\nLine two\nLine three"))
        end)
      end

      graph = transform.to_graph(diagram)

      plain_height = graph[:cards].find { |c| c[:id] == 'plain' }[:height]
      broken_height = graph[:cards].find { |c| c[:id] == 'broken' }[:height]

      expect(broken_height - plain_height).to eq(2 * described_class::EXTRA_LINE_HEIGHT)
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
    it "grows a column's height and its first card's y by one EXTRA_LINE_HEIGHT per embedded hard break in the title" do
      diagram = Sirena::Diagram::Kanban.new.tap do |d|
        d.add_column(Sirena::Diagram::KanbanColumn.new(id: 'plain', title: 'Todo').tap do |column|
          column.add_card(Sirena::Diagram::KanbanCard.new(id: 'card1', text: 'Card'))
        end)
        d.add_column(Sirena::Diagram::KanbanColumn.new(id: 'broken', title: "One\nTwo\nThree").tap do |column|
          column.add_card(Sirena::Diagram::KanbanCard.new(id: 'card2', text: 'Card'))
        end)
      end

      graph = transform.to_graph(diagram)

      plain_column = graph[:columns].find { |c| c[:id] == 'plain' }
      broken_column = graph[:columns].find { |c| c[:id] == 'broken' }
      plain_card = graph[:cards].find { |c| c[:column_id] == 'plain' }
      broken_card = graph[:cards].find { |c| c[:column_id] == 'broken' }

      expect(broken_column[:height] - plain_column[:height]).to eq(2 * described_class::EXTRA_LINE_HEIGHT)
      expect(broken_card[:y] - plain_card[:y]).to eq(2 * described_class::EXTRA_LINE_HEIGHT)
    end
  end
end
