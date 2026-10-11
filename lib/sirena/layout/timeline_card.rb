# frozen_string_literal: true

require "lutaml/model"
require_relative "timeline_line"
require_relative "timeline_rounding"

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
      # Canvas path data of the box, rounded top corners and open bottom.
      attribute :outline, :string
      # The rule under the box, on the canvas.
      attribute :rule, TimelineLine
      # Canvas anchor of the first text line, centred on the box.
      attribute :text_x, :float
      attribute :text_y, :float
      # Canvas baselines of the text lines after the first.
      attribute :next_baselines, :float, collection: true, default: -> { [] }

      CORNER = 5
      TEXT_TOP = 10
      FIRST_BASELINE = 21
      LINE_PITCH = 17.6

      # Moves the card, and its connector, by the given offsets.
      def shift(delta_x, delta_y)
        self.x += delta_x
        self.y += delta_y
        connector&.shift(delta_x, delta_y)
        place
      end

      # Publishes the canvas geometry the renderer draws from.
      def place
        settle
        self.outline = outline_path
        self.rule = rule_line
        place_text
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

      private

      def settle
        %i[x y width height text_width].each do |name|
          public_send(:"#{name}=", tidy(public_send(name)))
        end
        connector&.settle
      end

      def place_text
        self.text_x = tidy(x + (width / 2))
        self.text_y = tidy(y + TEXT_TOP + FIRST_BASELINE)
        self.next_baselines = baselines_after_first
      end

      def baselines_after_first
        (1...lines.length).map { |i| tidy(text_y + (i * LINE_PITCH)) }
      end

      def tidy(value)
        TimelineRounding.tidy(value)
      end

      def rule_line
        bottom_y = tidy(y + height)
        TimelineLine.new(x1: x, y1: bottom_y, x2: tidy(x + width),
                         y2: bottom_y)
      end

      def outline_path
        [start_command, "v#{path_number(CORNER + CORNER - height)}",
         "q0,-#{CORNER} #{CORNER},-#{CORNER}", "h#{path_number(width - 10)}",
         "q#{CORNER},0 #{CORNER},#{CORNER}", "v#{path_number(height - CORNER)}",
         "H#{path_number(x)}", "Z"].join(" ")
      end

      def start_command
        "M#{path_number(x)} #{path_number(y + height - CORNER)}"
      end

      def path_number(value)
        tidied = tidy(value)
        tidied.to_i == tidied ? tidied.to_i.to_s : tidied.to_s
      end
    end
  end
end
