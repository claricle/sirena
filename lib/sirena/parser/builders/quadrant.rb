# frozen_string_literal: true

require_relative "capture_string"
require_relative "../../diagram/quadrant"

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to Quadrant model.
      #
      # Converts the parse tree output from Grammars::Quadrant into a
      # fully-formed Diagram::Quadrant object with points and labels.
      class Quadrant
        include CaptureString

        STATEMENT_HANDLERS = {
          header: :process_header,
          title: :process_title,
          x_axis_left: :process_x_axis,
          y_axis_bottom: :process_y_axis,
          quadrant_label: :process_quadrant_label,
          data_point: :process_data_point,
        }.freeze

        HASH_STATEMENTS = %i[header title x_axis_left y_axis_bottom].freeze

        STYLE_EXTRACTORS = {
          radius: :extract_float,
          color: :extract_text,
          stroke_color: :extract_text,
          stroke_width: :extract_float,
        }.freeze

        QUADRANT_LABELS = {
          "1" => :quadrant_1_label,
          "2" => :quadrant_2_label,
          "3" => :quadrant_3_label,
          "4" => :quadrant_4_label,
        }.freeze

        # Transform parse tree into Quadrant diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::Quadrant] the quadrant chart diagram model
        def apply(tree)
          diagram = Diagram::Quadrant.new
          process_tree(diagram, tree)
          diagram
        end

        private

        def process_tree(diagram, tree)
          if tree.is_a?(Array)
            tree.each { |item| process_item(diagram, item, STATEMENT_HANDLERS) }
          elsif tree.is_a?(Hash)
            handlers = STATEMENT_HANDLERS.slice(*HASH_STATEMENTS)
            process_item(diagram, tree, handlers)
          end
        end

        def process_item(diagram, item, handlers)
          return unless item.is_a?(Hash)

          handlers.each do |key, handler|
            send(handler, diagram, item) if item.key?(key)
          end
        end

        def process_header(_diagram, _item)
          # Header is just the 'quadrantChart' keyword
        end

        def process_title(diagram, item)
          title_data = item[:title]
          return unless title_data

          title_text = extract_text(title_data)
          diagram.title = title_text unless title_text.empty?
        end

        def process_x_axis(diagram, item)
          diagram.x_axis_left = extract_text(item[:x_axis_left])
          diagram.x_axis_right = extract_text(item[:x_axis_right])
        end

        def process_y_axis(diagram, item)
          diagram.y_axis_bottom = extract_text(item[:y_axis_bottom])
          diagram.y_axis_top = extract_text(item[:y_axis_top])
        end

        def process_quadrant_label(diagram, item)
          attribute = QUADRANT_LABELS[item[:quadrant_number].to_s]
          return unless attribute

          label_text = extract_text(item[:quadrant_label])
          diagram.public_send("#{attribute}=", label_text)
        end

        def process_data_point(diagram, item)
          label = extract_text(item[:label])
          coords = item[:coordinates]
          return if label.empty? || coords.nil?

          point = build_point(label, coords, item[:styling])
          diagram.points << point
        end

        def build_point(label, coords, styling)
          Diagram::QuadrantPoint.new.tap do |point|
            point.label = label
            point.x = extract_float(coords[:x])
            point.y = extract_float(coords[:y])
            assign_point_style(point, extract_styling(styling))
          end
        end

        def assign_point_style(point, styling)
          styling.each do |attribute, value|
            point.public_send("#{attribute}=", value) if value
          end
        end

        def extract_styling(styling)
          styling_items(styling).each_with_object({}) do |item, result|
            next unless item.is_a?(Hash)

            STYLE_EXTRACTORS.each do |attribute, extractor|
              value = item[attribute]
              result[attribute] = send(extractor, value) if value
            end
          end
        end

        def styling_items(styling)
          return styling if styling.is_a?(Array)
          return [styling] if styling.is_a?(Hash)

          []
        end

        def extract_text(value)
          text = value.is_a?(Hash) ? extract_hash_text(value) : value.to_s
          text.strip
        end

        def extract_hash_text(value)
          return capture_string(value[:string]) if value[:string]

          value.values.first.to_s
        end

        def extract_float(value)
          value_str = if value.is_a?(Hash)
                        value.values.first.to_s
                      else
                        value.to_s
                      end

          value_str.to_f
        end
      end
    end
  end
end
