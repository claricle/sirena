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
    #
    # Card text kept well under `Renderer::MarkdownText::CARD_TEXT_CHAR_BUDGET`
    # (25 visible characters): this test is about the per-break growth, not
    # truncation — a longer fixture that itself crossed the budget would
    # have the renderer silently drop the third line, so the "one
    # EXTRA_LINE_HEIGHT per break" claim would no longer hold (see the
    # rendered_line_count-vs-truncation spec below for that case).
    it "grows a card's height by one EXTRA_LINE_HEIGHT per embedded hard break" do
      diagram = Sirena::Diagram::Kanban.new.tap do |d|
        d.add_column(Sirena::Diagram::KanbanColumn.new(id: 'todo', title: 'Todo').tap do |column|
          column.add_card(Sirena::Diagram::KanbanCard.new(id: 'plain', text: 'Plain card'))
          column.add_card(Sirena::Diagram::KanbanCard.new(id: 'broken', text: "One\nTwo\nThree"))
        end)
      end

      graph = transform.to_graph(diagram)

      plain_height = graph[:cards].find { |c| c[:id] == 'plain' }[:height]
      broken_height = graph[:cards].find { |c| c[:id] == 'broken' }[:height]

      expect(broken_height - plain_height).to eq(2 * described_class::EXTRA_LINE_HEIGHT)
    end

    # Codex round 5 High: card height used to be sized from a raw
    # `count("\n")`, which assumes every embedded line renders — but
    # `Renderer::Kanban#render_card_text` truncates a card's parsed lines to
    # `Renderer::MarkdownText::CARD_TEXT_CHAR_BUDGET` visible characters and
    # silently drops whole lines past that budget. A card whose text crosses
    # the budget across 3 newline-delimited lines only ever renders 2 of
    # them (`"Line one\nLine two\nLine three"` sums to 26 visible characters,
    # one over the 25-character budget — verified directly against
    # `Renderer::MarkdownText.truncate_runs` before writing this), so it
    # should only grow by ONE `EXTRA_LINE_HEIGHT`, not two.
    #
    # Mutation-check: replace `rendered_line_count(card.text)` with
    # `card.text.to_s.count("\n") + 1` (the pre-fix raw-newline count) in
    # `calculate_card_height`. Watched red: this comes back needing TWO
    # `EXTRA_LINE_HEIGHT`s instead of one.
    #
    # This example alone doesn't pin the truncation-aware line count
    # specifically — a naive under-budget line count (e.g. capping at 2
    # regardless of the actual budget) also passes it. It's the sibling
    # example above ("grows a card's height by one EXTRA_LINE_HEIGHT per
    # embedded hard break", an under-budget 3-line card) that catches that
    # narrower mutation; the two together pin the real property.
    it "grows a card's height only by the lines the renderer's own truncation actually keeps" do
      diagram = Sirena::Diagram::Kanban.new.tap do |d|
        d.add_column(Sirena::Diagram::KanbanColumn.new(id: 'todo', title: 'Todo').tap do |column|
          column.add_card(Sirena::Diagram::KanbanCard.new(id: 'plain', text: 'Plain card'))
          column.add_card(Sirena::Diagram::KanbanCard.new(id: 'over_budget', text: "Line one\nLine two\nLine three"))
        end)
      end

      graph = transform.to_graph(diagram)

      plain_height = graph[:cards].find { |c| c[:id] == 'plain' }[:height]
      over_budget_height = graph[:cards].find { |c| c[:id] == 'over_budget' }[:height]

      expect(over_budget_height - plain_height).to eq(described_class::EXTRA_LINE_HEIGHT)
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
