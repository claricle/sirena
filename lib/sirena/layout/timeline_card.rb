# frozen_string_literal: true

require "lutaml/model"
require_relative "timeline_line"

module Sirena
  module Layout
    # One timeline box: a section, a period or an event.
    class TimelineCard < Lutaml::Model::Serializable
      attribute :kind, :string
      attribute :lines, :string, collection: true, default: -> { [] }
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float
      attribute :text_width, :float
      attribute :color_index, :integer
      attribute :font_size, :float
      # The dashed line a period drops towards its events.
      attribute :connector, TimelineLine

      # Moves the card, and its connector, by the given offsets.
      def shift(delta_x, delta_y)
        self.x += delta_x
        self.y += delta_y
        connector&.shift(delta_x, delta_y)
      end

      # @return [Float] x range the box and its text cover
      def x_range
        reach = [width, text_width].max
        middle = x + (width / 2)
        [middle - (reach / 2), middle + (reach / 2)]
      end

      # @return [Float] lowest y the box or its connector reaches
      def bottom
        [y + height, connector&.y2].compact.max
      end
    end
  end
end
