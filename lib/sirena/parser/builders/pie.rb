# frozen_string_literal: true

require_relative "capture_string"
require_relative "../../diagram/pie"

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to Pie diagram model.
      #
      # Converts the parse tree output from Grammars::Pie into a
      # fully-formed Diagram::Pie object with slices and metadata.
      class Pie
        include CaptureString

        # Transform parse tree into Pie diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::Pie] the pie chart diagram model
        def apply(tree)
          diagram = Diagram::Pie.new

          # A bare header parses to one Hash; header plus statements
          # to an Array.
          [tree].flatten(1).each do |item|
            process_title(diagram, item) if item.key?(:title)
            process_show_data(diagram, item) if item.key?(:show_data)
            process_statement(diagram, item)
          end

          diagram
        end

        private

        def process_title(diagram, item)
          title_data = item[:title]
          return unless title_data

          # Extract title text
          title_text = if title_data.is_a?(Hash)
                         extract_text(title_data[:title])
                       else
                         extract_text(title_data)
                       end

          diagram.title = title_text unless title_text.empty?
        end

        def process_show_data(diagram, item)
          show_data = item[:show_data]
          return unless show_data

          # showData flag is present if this key exists
          diagram.show_data = true
        end

        def process_statement(diagram, stmt)
          if stmt[:data_entry]
            add_data_entry(diagram, stmt)
          elsif stmt[:acc_title]
            diagram.acc_title = extract_text(stmt[:acc_title])
          elsif stmt[:acc_descr]
            diagram.acc_description = extract_text(stmt[:acc_descr])
          elsif stmt[:standalone_title]
            diagram.title = extract_text(stmt[:standalone_title])
          end
        end

        def add_data_entry(diagram, stmt)
          label = extract_text(stmt[:label])
          value = extract_numeric_value(stmt[:value])

          slice = Diagram::PieSlice.new.tap do |s|
            s.label = label
            s.value = value
          end

          diagram.slices << slice
        end

        def extract_text(value)
          case value
          when Hash then capture_string(value[:string])
          when String then value
          else value.to_s
          end.strip
        end

        def extract_numeric_value(value)
          value.to_s.to_f
        end
      end
    end
  end
end
