# frozen_string_literal: true

require_relative "base"
require_relative "../markdown_text"

module Sirena
  module Layout
    # Builds final-canvas Kanban board geometry.
    class Kanban < Base
      COLUMN_HORIZONTAL_SPACING = 60
      CARD_VERTICAL_SPACING = 15
      COLUMN_WIDTH = 200
      COLUMN_HEADER_HEIGHT = 50
      COLUMN_PADDING = 10
      CARD_HEIGHT = 80
      CARD_PADDING = 10
      EXTRA_LINE_HEIGHT = 18
      CANVAS_PADDING = 40

      class Box < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
        attribute :style, :string
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :font_weight, :string
        attribute :style, :string
      end

      class Column < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :background, Box
        attribute :header, Box
        attribute :title, Label
        attribute :badge, Box
        attribute :badge_label, Label
      end

      class Card < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :column_id, :string
        attribute :background, Box
        attribute :label, Label
        attribute :metadata, Label, collection: true, default: -> { [] }
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :columns, Column, collection: true, default: -> { [] }
        attribute :cards, Card, collection: true, default: -> { [] }
      end

      # Builds a Scene from the released positioned-Hash surface. Hash access
      # remains in Layout; Renderer receives typed final geometry only.
      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Retains the pre-Scene structure for direct callers during conversion.
      def build_graph(diagram)
        return empty_graph if diagram.columns.nil? || diagram.columns.empty?

        columns = position_columns(diagram.columns)
        cards = position_cards(columns)
        bounds = calculate_bounds(columns)
        { columns: columns, cards: cards, width: bounds[:width], height: bounds[:height] }
      end

      private

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def scene_from_graph(graph)
        width = graph.fetch(:width) + (CANVAS_PADDING * 2)
        height = graph.fetch(:height) + (CANVAS_PADDING * 2)
        Scene.new(
          width: width, height: height, view_box: "0 0 #{width} #{height}",
          columns: graph.fetch(:columns).map { |column| typed_column(column) },
          cards: graph.fetch(:cards).map { |card| typed_card(card) }
        )
      end

      def typed_column(column)
        x = column[:x] + CANVAS_PADDING
        y = column[:y] + CANVAS_PADDING
        header_size = font_size(:font_size_normal, 14)
        title_lines = Sirena::MarkdownText.parse_lines(column[:title])

        Column.new(
          id: column[:id],
          background: box(x, y, column[:width], column[:height], 8, "column"),
          header: box(x, y, column[:width], column[:header_height], 8, "header"),
          title: label(
            column[:title], x + (column[:width] / 2.0),
            header_text_baseline(y, column[:header_height], title_lines.length,
                                 header_size),
            header_size, "header", anchor: "middle", weight: "bold"
          ),
          badge: badge_box(column, x, y),
          badge_label: badge_label(column, x, y),
        )
      end

      def badge_box(column, x, y)
        return unless column[:card_count].positive?

        box(x + column[:width] - 25, y + 15, 20, 20, 10, "badge")
      end

      def badge_label(column, x, y)
        return unless column[:card_count].positive?

        label(
          column[:card_count].to_s, x + column[:width] - 15, y + 29,
          font_size(:font_size_small, 11), "badge", anchor: "middle",
                                                    weight: "bold"
        )
      end

      def typed_card(card)
        x = card[:x] + CANVAS_PADDING
        y = card[:y] + CANVAS_PADDING
        lines = rendered_lines(card[:text])
        Card.new(
          id: card[:id], column_id: card[:column_id],
          background: box(x, y, card[:width], card[:height], 6, "card"),
          label: label(card[:text], x + 10, y + 25,
                       font_size(:font_size_normal, 13), "card"),
          metadata: metadata_labels(card, x, y, lines.length)
        )
      end

      def metadata_labels(card, x, y, label_line_count)
        return [] unless card[:has_metadata]

        start_y = y + 50 + ([label_line_count - 1, 0].max * line_height)
        card[:metadata].each_with_index.flat_map do |(key, value), index|
          next [] if value.nil? || value.to_s.empty?

          current_y = start_y + (index * line_height)
          [
            label("#{format_metadata_key(key)}:", x + 10, current_y,
                  font_size(:font_size_small, 10), "metadata_label"),
            label(value.to_s, x + 70, current_y,
                  font_size(:font_size_small, 10), "metadata_value",
                  weight: "bold"),
          ]
        end
      end

      def box(x, y, width, height, radius, style)
        Box.new(
          x: x, y: y, width: width, height: height,
          corner_radius: radius, style: style
        )
      end

      def label(text, x, y, size, style, **options)
        Label.new(
          text: text, x: x, y: y, font_size: size, style: style,
          text_anchor: options[:anchor], font_weight: options[:weight]
        )
      end

      def header_text_baseline(y, height, line_count, font_size)
        rendered_line_height = font_size * 1.2
        y + (height / 2.0) + 5 -
          ((line_count - 1) * rendered_line_height / 2.0)
      end

      def empty_graph
        { columns: [], cards: [], width: 0, height: 0 }
      end

      def position_columns(columns)
        columns.map.with_index do |column, index|
          header_height = calculate_header_height(column)
          {
            id: column.id, title: column.title,
            x: index * (COLUMN_WIDTH + COLUMN_HORIZONTAL_SPACING), y: 0,
            width: COLUMN_WIDTH,
            height: calculate_column_height(column, header_height),
            header_height: header_height, card_count: column.cards.size,
            original: column
          }
        end
      end

      def position_cards(columns)
        columns.flat_map do |column_data|
          column = column_data[:original]
          current_y = column_data[:header_height] + COLUMN_PADDING
          column.cards.map do |card|
            height = calculate_card_height(card)
            positioned = {
              id: card.id, text: card.text, column_id: column.id,
              x: column_data[:x] + COLUMN_PADDING, y: current_y,
              width: COLUMN_WIDTH - (COLUMN_PADDING * 2), height: height,
              metadata: card.metadata, has_metadata: card.has_metadata?,
              original: card
            }
            current_y += height + CARD_VERTICAL_SPACING
            positioned
          end
        end
      end

      def calculate_header_height(column)
        COLUMN_HEADER_HEIGHT + (column.title.to_s.count("\n") * line_height)
      end

      def calculate_column_height(column, header_height)
        return header_height + COLUMN_PADDING if column.cards.empty?

        card_height = column.cards.sum { |card| calculate_card_height(card) }
        spacing = (column.cards.size - 1) * CARD_VERTICAL_SPACING
        header_height + COLUMN_PADDING + card_height + spacing + COLUMN_PADDING
      end

      def calculate_card_height(card)
        height = CARD_HEIGHT
        height += card.metadata.size * line_height if card.has_metadata?
        height + ((rendered_lines(card.text).length - 1) * line_height)
      end

      def rendered_lines(text)
        Sirena::MarkdownText.truncate_runs(
          Sirena::MarkdownText.parse_lines(text),
          Sirena::MarkdownText::CARD_TEXT_CHAR_BUDGET,
        )
      end

      def line_height
        font_size(:font_size_small, 12) * (typography_value(:line_height) || 1.5)
      end

      def font_size(name, fallback)
        value = typography_value(name) || typography_value(:font_size)
        value&.positive? ? value : fallback
      end

      def typography_value(name)
        typography = theme.typography
        typography.public_send(name) if typography.respond_to?(name)
      end

      def calculate_bounds(columns)
        return { width: 0, height: 0 } if columns.empty?

        {
          width: columns.map { |column| column[:x] + column[:width] }.max,
          height: columns.map { |column| column[:height] }.max,
        }
      end

      def format_metadata_key(key)
        key.to_s.capitalize
      end
    end
  end
end
