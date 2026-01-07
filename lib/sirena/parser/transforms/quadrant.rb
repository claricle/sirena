# frozen_string_literal: true

require_relative '../../diagram/quadrant'

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to QuadrantChart model.
      #
      # Converts the parse tree output from Grammars::Quadrant into a
      # fully-formed Diagram::QuadrantChart object with points and labels.
      class Quadrant
        # Transform parse tree into QuadrantChart diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::QuadrantChart] the quadrant chart diagram model
        def apply(tree)
          diagram = Diagram::QuadrantChart.new

          # Tree structure: array with header and statements
          if tree.is_a?(Array)
            tree.each do |item|
              next unless item.is_a?(Hash)

              process_header(diagram, item) if item.key?(:header)
              process_title(diagram, item) if item.key?(:title)
              process_x_axis(diagram, item) if item.key?(:x_axis_left)
              process_y_axis(diagram, item) if item.key?(:y_axis_bottom)
              process_quadrant_label(diagram, item) if item.key?(:quadrant_label)
              process_data_point(diagram, item) if item.key?(:data_point)
            end
          elsif tree.is_a?(Hash)
            process_header(diagram, tree) if tree.key?(:header)
            process_title(diagram, tree) if tree.key?(:title)
            process_x_axis(diagram, tree) if tree.key?(:x_axis_left)
            process_y_axis(diagram, tree) if tree.key?(:y_axis_bottom)

            if tree[:statements]
              process_statements(diagram, tree[:statements])
            end
          end

          diagram
        end

        private

        def process_header(diagram, item)
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
          quadrant_num = item[:quadrant_number].to_s
          label_text = extract_text(item[:quadrant_label])

          case quadrant_num
          when '1'
            diagram.quadrant_1_label = label_text
          when '2'
            diagram.quadrant_2_label = label_text
          when '3'
            diagram.quadrant_3_label = label_text
          when '4'
            diagram.quadrant_4_label = label_text
          end
        end

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            next unless stmt.is_a?(Hash)

            process_title(diagram, stmt) if stmt.key?(:title)
            process_x_axis(diagram, stmt) if stmt.key?(:x_axis_left)
            process_y_axis(diagram, stmt) if stmt.key?(:y_axis_bottom)
            process_quadrant_label(diagram, stmt) if stmt.key?(:quadrant_label)
            process_data_point(diagram, stmt) if stmt.key?(:data_point)
          end
        end

        def process_data_point(diagram, item)
          label = extract_text(item[:label])
          coords = item[:coordinates]
          styling = item[:styling]

          return if label.empty? || coords.nil?

          x = extract_float(coords[:x])
          y = extract_float(coords[:y])

          point = Diagram::QuadrantPoint.new.tap do |p|
            p.label = label
            p.x = x
            p.y = y

            # Process optional styling parameters
            if styling
              style_hash = extract_styling(styling)
              p.radius = style_hash[:radius] if style_hash[:radius]
              p.color = style_hash[:color] if style_hash[:color]
              p.stroke_color = style_hash[:stroke_color] if style_hash[:stroke_color]
              p.stroke_width = style_hash[:stroke_width] if style_hash[:stroke_width]
            end
          end

          diagram.points << point
        end

        def extract_styling(styling)
          result = {}

          # Styling can be a Hash or Array depending on parse tree structure
          items = if styling.is_a?(Array)
                    styling
                  elsif styling.is_a?(Hash)
                    [styling]
                  else
                    []
                  end

          items.each do |item|
            next unless item.is_a?(Hash)

            result[:radius] = extract_float(item[:radius]) if item[:radius]
            result[:color] = extract_text(item[:color]) if item[:color]
            result[:stroke_color] = extract_text(item[:stroke_color]) if item[:stroke_color]
            result[:stroke_width] = extract_float(item[:stroke_width]) if item[:stroke_width]
          end

          result
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end.strip
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