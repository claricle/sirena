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
  end
end
