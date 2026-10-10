# frozen_string_literal: true

require_relative "base"
require_relative "kanban_card_text"
require_relative "../markdown_text"
require_relative "../notation/mermaid/ir_adapters/kanban"

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

      METADATA_KEYS = {
        "assignee" => :assigned,
        "ticket_reference" => :ticket,
        "icon" => :icon,
        "secondary_label" => :label,
        "priority" => :priority,
      }.freeze
      private_constant :METADATA_KEYS

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
        attribute :wrap_width, :float
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
        data = ir_data(diagram)
        return empty_graph if board_columns(data).empty?

        columns = position_columns(data)
        cards = position_cards(columns, data)
        bounds = calculate_bounds(columns)
        {
          columns: columns, cards: cards,
          width: bounds[:width], height: bounds[:height]
        }
      end

      private

      def ir_data(diagram)
        return diagram if diagram.is_a?(IR::Data)

        Notation::Mermaid::IRAdapters::Kanban.call(diagram)
      end

      def board_columns(data)
        data.items.select { |item| item.role == "board_column" }
      end

      def column_cards(data, column)
        data.items.select do |item|
          item.role == "work_item" && item.parent_id == column.id
        end
      end

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
        position = canvas_position(column)

        Column.new(
          id: column[:id],
          background: column_background(column, position),
          header: column_header(column, position),
          title: column_title(column, position),
          badge: badge_box(column, position),
          badge_label: badge_label(column, position),
        )
      end

      def column_background(column, position)
        box(
          position, column[:width], column[:height],
          radius: 8, style: "column"
        )
      end

      def column_header(column, position)
        box(
          position, column[:width], column[:header_height],
          radius: 8, style: "header"
        )
      end

      def column_title(column, position)
        font_size = font_size(:font_size_normal, 14)
        line_count = Sirena::MarkdownText.parse_lines(column[:title]).length
        title_position = [
          position[0] + (column[:width] / 2.0),
          header_text_baseline(position[1], column[:header_height],
                               line_count, font_size),
        ]
        label(
          column[:title], title_position, font_size, "header",
          anchor: "middle", weight: "bold"
        )
      end

      def badge_box(column, position)
        return unless column[:card_count].positive?

        badge_position = [position[0] + column[:width] - 25, position[1] + 15]
        box(badge_position, 20, 20, radius: 10, style: "badge")
      end

      def badge_label(column, position)
        return unless column[:card_count].positive?

        badge_position = [position[0] + column[:width] - 15, position[1] + 29]
        label(
          column[:card_count].to_s, badge_position,
          font_size(:font_size_small, 11), "badge",
          anchor: "middle", weight: "bold"
        )
      end

      def typed_card(card)
        position = canvas_position(card)
        Card.new(
          id: card[:id], column_id: card[:column_id],
          background: box(
            position, card[:width], card[:height], radius: 6, style: "card"
          ),
          label: card_label(card, position),
          metadata: metadata_labels(card, position)
        )
      end

      def card_label(card, position)
        label_position = [position[0] + 10, position[1] + 25]
        label(
          card[:text], label_position, font_size(:font_size_normal, 13), "card",
          wrap_width: text_width(card[:width])
        )
      end

      def text_width(card_width)
        card_width - (CARD_PADDING * 2)
      end

      def metadata_labels(card, position)
        return [] unless card[:has_metadata]

        start_y = metadata_start_y(card[:text], position[1])
        card[:metadata].each_with_index.flat_map do |(key, value), index|
          metadata_label_pair(key, value, position[0], start_y, index)
        end
      end

      def metadata_start_y(text, y_position)
        extra_lines = [rendered_lines(text).length - 1, 0].max
        y_position + 50 + (extra_lines * line_height)
      end

      def metadata_label_pair(key, value, x_position, start_y, index)
        return [] if value.nil? || value.to_s.empty?

        y_position = start_y + (index * line_height)
        size = font_size(:font_size_small, 10)
        [
          label("#{format_metadata_key(key)}:", [x_position + 10, y_position],
                size, "metadata_label"),
          label(value.to_s, [x_position + 70, y_position], size,
                "metadata_value", weight: "bold"),
        ]
      end

      def box(position, width, height, radius:, style:)
        Box.new(
          x: position[0], y: position[1], width: width, height: height,
          corner_radius: radius, style: style
        )
      end

      def label(text, position, size, style, **options)
        Label.new(
          text: text, x: position[0], y: position[1],
          font_size: size, style: style,
          text_anchor: options[:anchor], font_weight: options[:weight],
          wrap_width: options[:wrap_width]
        )
      end

      def header_text_baseline(y_position, height, line_count, font_size)
        rendered_line_height = font_size * 1.2
        y_position + (height / 2.0) + 5 -
          ((line_count - 1) * rendered_line_height / 2.0)
      end

      def canvas_position(item)
        [item[:x] + CANVAS_PADDING, item[:y] + CANVAS_PADDING]
      end

      def empty_graph
        { columns: [], cards: [], width: 0, height: 0 }
      end

      def position_columns(data)
        board_columns(data).map.with_index do |column, index|
          positioned_column(data, column, index)
        end
      end

      def positioned_column(data, column, index)
        cards = column_cards(data, column)
        header_height = calculate_header_height(column.label)
        {
          id: column.id, title: column.label,
          x: index * (COLUMN_WIDTH + COLUMN_HORIZONTAL_SPACING), y: 0,
          width: COLUMN_WIDTH,
          height: calculate_column_height(cards, header_height, data),
          header_height: header_height, card_count: cards.size, cards: cards
        }
      end

      def position_cards(columns, data)
        columns.flat_map do |column_data|
          positioned_cards(column_data, data)
        end
      end

      def positioned_cards(column_data, data)
        current_y = column_data[:header_height] + COLUMN_PADDING
        column_data[:cards].map do |card|
          positioned = positioned_card(card, column_data, current_y, data)
          current_y += positioned[:height] + CARD_VERTICAL_SPACING
          positioned
        end
      end

      def positioned_card(card, column_data, y_position, data)
        metadata = metadata_for(data, card)
        {
          id: card.id, text: card.label, column_id: column_data[:id],
          x: column_data[:x] + COLUMN_PADDING, y: y_position,
          width: COLUMN_WIDTH - (COLUMN_PADDING * 2),
          height: calculate_card_height(card.label, metadata),
          metadata: metadata, has_metadata: !metadata.empty?
        }
      end

      def metadata_for(data, card)
        data.values.each_with_object({}) do |value, metadata|
          key = METADATA_KEYS[value.role]
          metadata[key] = value.value.value if key && value.parent_id == card.id
        end
      end

      def calculate_header_height(title)
        COLUMN_HEADER_HEIGHT + (title.to_s.count("\n") * line_height)
      end

      def calculate_column_height(cards, header_height, data)
        return header_height + COLUMN_PADDING if cards.empty?

        card_height = cards.sum do |card|
          calculate_card_height(card.label, metadata_for(data, card))
        end
        spacing = (cards.size - 1) * CARD_VERTICAL_SPACING
        header_height + COLUMN_PADDING + card_height + spacing + COLUMN_PADDING
      end

      def calculate_card_height(text, metadata)
        height = CARD_HEIGHT
        height += metadata.size * line_height unless metadata.empty?
        height + ((rendered_lines(text).length - 1) * line_height)
      end

      def rendered_lines(text)
        KanbanCardText.lines(
          text, width: text_width(COLUMN_WIDTH - (COLUMN_PADDING * 2)),
                font_size: font_size(:font_size_normal, 13)
        )
      end

      def line_height
        multiplier = typography_value(:line_height) || 1.5
        font_size(:font_size_small, 12) * multiplier
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
