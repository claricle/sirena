# frozen_string_literal: true

require_relative '../../diagram/pie'

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to Pie diagram model.
      #
      # Converts the parse tree output from Grammars::Pie into a
      # fully-formed Diagram::Pie object with slices and metadata.
      class Pie
        # Transform parse tree into Pie diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::Pie] the pie chart diagram model
        def apply(tree)
          diagram = Diagram::Pie.new

          # Tree structure: array with header and statements
          if tree.is_a?(Array)
            tree.each do |item|
              next unless item.is_a?(Hash)

              process_header(diagram, item) if item.key?(:header)
              process_title(diagram, item) if item.key?(:title)
              process_show_data(diagram, item) if item.key?(:show_data)
              process_statement(diagram, item) if statement?(item)
            end
          elsif tree.is_a?(Hash)
            process_header(diagram, tree) if tree.key?(:header)
            process_title(diagram, tree) if tree.key?(:title)
            process_show_data(diagram, tree) if tree.key?(:show_data)

            if tree[:statements]
              process_statements(diagram, tree[:statements])
            end
          end

          diagram
        end

        private

        def statement?(item)
          item.key?(:data_entry) ||
            item.key?(:acc_title) ||
            item.key?(:acc_descr) ||
            item.key?(:standalone_title)
        end

        def process_header(diagram, item)
          # Header is just the 'pie' keyword, nothing to extract
        end

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

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_statement(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)

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

          return if label.empty?

          slice = Diagram::PieSlice.new.tap do |s|
            s.label = label
            s.value = value
          end

          diagram.slices << slice
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            elsif value[:title]
              value[:title].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end.strip
        end

        def extract_numeric_value(value)
          # Value can be a simple string or a complex structure
          value_str = if value.is_a?(Hash)
                        value.values.first.to_s
                      else
                        value.to_s
                      end

          # Parse as float to handle both integers and decimals
          value_str.to_f
        end
      end
    end
  end
end