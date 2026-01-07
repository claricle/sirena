# frozen_string_literal: true

require_relative '../../diagram/c4'

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to C4 diagram model.
      #
      # Converts the parse tree output from Grammars::C4 into a
      # fully-formed Diagram::C4 object with elements, relationships, and
      # boundaries.
      class C4
        def initialize
          @boundary_stack = []
          @current_boundary = nil
        end

        # Transform parse tree into C4 diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::C4] the C4 diagram model
        def apply(tree)
          diagram = Diagram::C4.new
          @boundary_stack = []
          @current_boundary = nil

          # Extract level from header
          extract_level(diagram, tree)

          # Process statements - collect scattered attributes
          if tree.is_a?(Array)
            # Merge scattered attribute hashes with their parent element/boundary
            merged_tree = merge_scattered_attributes(tree)
            merged_tree.each do |item|
              process_statement(diagram, item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash)
            process_statement(diagram, tree)
          end

          diagram
        end

        private

        # Merge scattered attribute hashes into their parent statements
        def merge_scattered_attributes(tree)
          result = []
          i = 0
          while i < tree.length
            item = tree[i]
            
            # Check if this is an element/boundary statement starter
            if item.is_a?(Hash) && (item[:element_type] || item[:boundary_type])
              # Don't merge if this has a body (it's a complete boundary statement)
              if item[:body]
                result << item
                i += 1
                next
              end
              
              # Look ahead and merge all related hashes
              j = i + 1
              while j < tree.length && tree[j].is_a?(Hash)
                next_item = tree[j]
                # Stop if we hit another element/boundary/relationship/title/config
                break if next_item[:element_type] || next_item[:boundary_type] ||
                         next_item[:rel_type] || next_item[:title] ||
                         next_item[:config_params] || next_item[:header]
                # Merge this hash into the current statement
                item = item.merge(next_item)
                j += 1
              end
              result << item
              i = j
            else
              result << item
              i += 1
            end
          end
          result
        end

        def extract_level(diagram, tree)
          header = if tree.is_a?(Array)
                     tree.find { |item| item.is_a?(Hash) && item[:header] }
                   elsif tree.is_a?(Hash) && tree[:header]
                     tree
                   end

          if header && header[:header]
            header_str = header[:header].to_s
            diagram.level = case header_str
                            when 'C4Context'
                              'Context'
                            when 'C4Container'
                              'Container'
                            when 'C4Component'
                              'Component'
                            when 'C4Dynamic'
                              'Dynamic'
                            when 'C4Deployment'
                              'Deployment'
                            when 'C4 diagram'
                              'Context' # Default
                            else
                              'Context'
                            end
          end
        end

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)

          if stmt[:header]
            # Already processed
            nil
          elsif stmt[:title]
            diagram.title = extract_text(stmt[:title])
          elsif stmt[:config_params]
            process_layout_config(diagram, stmt)
          elsif stmt[:boundary_type]
            process_boundary(diagram, stmt)
          elsif stmt[:rel_type]
            process_relationship(diagram, stmt)
          elsif stmt[:element_type]
            process_element(diagram, stmt)
          end
        end

        def process_layout_config(diagram, stmt)
          # Extract layout config as a simple string
          config_parts = []
          if stmt[:config_params].is_a?(Array)
            stmt[:config_params].each do |param|
              key = extract_text(param[:key]) if param[:key]
              value = extract_text(param[:value]) if param[:value]
              config_parts << "#{key}=#{value}" if key && value
            end
          elsif stmt[:config_params].is_a?(Hash)
            key = extract_text(stmt[:config_params][:key])
            value = extract_text(stmt[:config_params][:value])
            config_parts << "#{key}=#{value}"
          end

          diagram.layout_config = config_parts.join(', ')
        end

        def process_boundary(diagram, stmt)
          boundary = Diagram::C4Boundary.new

          # Handle boundary type (can be a variable reference)
          boundary_type = stmt[:boundary_type]
          if boundary_type.is_a?(Hash) && boundary_type[:variable]
            # Variable reference like ${macroName}
            boundary.boundary_type = extract_text(boundary_type[:variable][:var])
          else
            boundary.boundary_type = boundary_type.to_s
          end

          boundary.id = extract_text(stmt[:id]) if stmt[:id]
          boundary.label = extract_text(stmt[:label]) if stmt[:label]
          boundary.type_param = extract_text(stmt[:type]) if stmt[:type]
          boundary.link = extract_text(stmt[:link]) if stmt[:link]
          boundary.tags = extract_text(stmt[:tags]) if stmt[:tags]

          # Set parent if we're inside another boundary
          boundary.parent_id = @current_boundary if @current_boundary

          # Add boundary to diagram
          diagram.boundaries << boundary

          # Process nested content
          if stmt[:body]
            old_boundary = @current_boundary
            @current_boundary = boundary.id

            # Normalize body to array of items
            body_array = stmt[:body].is_a?(Array) ? stmt[:body] : [stmt[:body]]
            
            # Extract items from the body structure
            body_items = body_array.flat_map do |item|
              if item.is_a?(Hash) && item[:item]
                [item[:item]]
              else
                []
              end
            end

            # Merge scattered attributes in the body
            merged_body = merge_scattered_attributes(body_items)

            # Process each merged item
            merged_body.each do |nested_item|
              if nested_item[:boundary_type]
                # Nested boundary
                nested_boundary_id = process_nested_boundary(diagram,
                                                              nested_item)
                boundary.boundary_ids << nested_boundary_id if
                  nested_boundary_id
              elsif nested_item[:element_type]
                # Element inside boundary
                element_id = process_nested_element(diagram, nested_item)
                boundary.element_ids << element_id if element_id
              end
            end

            @current_boundary = old_boundary
          end
        end

        def process_nested_boundary(diagram, stmt)
          boundary = Diagram::C4Boundary.new

          # Handle boundary type (can be a variable reference)
          boundary_type = stmt[:boundary_type]
          if boundary_type.is_a?(Hash) && boundary_type[:variable]
            # Variable reference like ${macroName}
            boundary.boundary_type = extract_text(boundary_type[:variable][:var])
          else
            boundary.boundary_type = boundary_type.to_s
          end

          boundary.id = extract_text(stmt[:id]) if stmt[:id]
          boundary.label = extract_text(stmt[:label]) if stmt[:label]
          boundary.type_param = extract_text(stmt[:type]) if stmt[:type]
          boundary.link = extract_text(stmt[:link]) if stmt[:link]
          boundary.tags = extract_text(stmt[:tags]) if stmt[:tags]
          boundary.parent_id = @current_boundary

          diagram.boundaries << boundary

          # Process nested content recursively
          if stmt[:body]
            old_boundary = @current_boundary
            @current_boundary = boundary.id

            # Convert body to array and extract items
            body_items = Array(stmt[:body]).flat_map do |item|
              if item.is_a?(Hash) && item[:item]
                [item[:item]]
              else
                []
              end
            end

            # Merge scattered attributes in the body
            merged_body = merge_scattered_attributes(body_items)

            # Process each merged item
            merged_body.each do |nested_item|
              if nested_item[:boundary_type]
                nested_boundary_id = process_nested_boundary(diagram,
                                                              nested_item)
                boundary.boundary_ids << nested_boundary_id if
                  nested_boundary_id
              elsif nested_item[:element_type]
                element_id = process_nested_element(diagram, nested_item)
                boundary.element_ids << element_id if element_id
              end
            end

            @current_boundary = old_boundary
          end

          boundary.id
        end

        def process_element(diagram, stmt)
          element = create_element(stmt)
          element.boundary_id = @current_boundary if @current_boundary
          diagram.elements << element
        end

        def process_nested_element(diagram, stmt)
          element = create_element(stmt)
          element.boundary_id = @current_boundary if @current_boundary
          diagram.elements << element
          element.id
        end

        def create_element(stmt)
          element = Diagram::C4Element.new

          # Extract element type
          element_type = stmt[:element_type]
          if element_type.is_a?(Hash) && element_type[:variable]
            # Handle ${macroName} variable references (used in tests)
            element.element_type = extract_text(element_type[:variable][:var])
          else
            element.element_type = element_type.to_s
          end

          # Extract parameters
          element.id = extract_text(stmt[:id]) if stmt[:id]
          element.label = extract_text(stmt[:label]) if stmt[:label]
          element.description = extract_text(stmt[:description]) if
            stmt[:description]
          element.technology = extract_text(stmt[:technology]) if
            stmt[:technology]

          # Extract attributes
          element.sprite = extract_text(stmt[:sprite]) if stmt[:sprite]
          element.link = extract_text(stmt[:link]) if stmt[:link]
          element.tags = extract_text(stmt[:tags]) if stmt[:tags]

          # Set external flag based on element type
          element.external = element.element_type&.end_with?('_Ext') || false

          element
        end

        def process_relationship(diagram, stmt)
          relationship = Diagram::C4Relationship.new

          relationship.rel_type = stmt[:rel_type].to_s
          relationship.from_id = extract_text(stmt[:from]) if stmt[:from]
          relationship.to_id = extract_text(stmt[:to]) if stmt[:to]
          relationship.label = extract_text(stmt[:label]) if stmt[:label]
          relationship.technology = extract_text(stmt[:technology]) if
            stmt[:technology]

          diagram.relationships << relationship
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            elsif value[:var]
              # Variable reference like ${macroName}
              value[:var].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end.strip
        end
      end
    end
  end
end