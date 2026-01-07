# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Transforms
      # Transform for Mindmap diagrams
      class Mindmap < Parslet::Transform
        # Helper class to build mindmap tree from indented nodes
        class TreeBuilder
          attr_reader :root, :all_nodes

          def initialize
            @all_nodes = []
            @root = nil
            @level_stack = []
            @pending_icon = nil
            @pending_classes = []
            @min_indent = nil
          end

          def add_node(node_data)
            # Handle icon and class declarations - apply to PREVIOUS node
            if node_data[:icon]
              icon = node_data[:icon].to_s
              if @all_nodes.last
                @all_nodes.last[:icon] = icon
              end
              return
            end

            if node_data[:classes]
              classes_str = node_data[:classes].to_s
              classes = classes_str.split(/\s+/)
              if @all_nodes.last
                @all_nodes.last[:classes] = classes
              end
              return
            end

            # Track minimum indentation for relative level calculation
            indent_size = get_indent_size(node_data[:indent])
            @min_indent = indent_size if @min_indent.nil? || indent_size < @min_indent

            # Calculate level from indentation (will be adjusted later)
            level = calculate_level(node_data[:indent])

            # Create the node
            content = extract_content(node_data)
            shape = extract_shape(node_data)

            node = {
              id: "node-#{@all_nodes.size}",
              content: content,
              level: level,
              shape: shape,
              icon: nil,
              classes: [],
              children: [],
              _indent_size: indent_size  # Store for later adjustment
            }

            @all_nodes << node

            # Build hierarchy
            if level == 0
              @root = node
              @level_stack = [node]
            else
              # Find parent at previous level
              parent = find_parent(level)
              if parent
                parent[:children] << node
                node[:parent] = parent
              end

              # Update stack
              @level_stack = @level_stack[0..level - 1] + [node]
            end
          end

          def finalize
            # Adjust all levels to be relative to minimum indentation
            return if @min_indent.nil?

            @all_nodes.each do |node|
              indent_size = node.delete(:_indent_size)
              node[:level] = calculate_relative_level(indent_size, @min_indent)
            end

            # Rebuild hierarchy with corrected levels
            rebuild_hierarchy
          end

          private

          def rebuild_hierarchy
            @root = nil
            @level_stack = []

            @all_nodes.each do |node|
              level = node[:level]

              # Clear old parent/children relationships
              node[:children] = []
              node.delete(:parent)

              if level == 0
                @root = node
                @level_stack = [node]
              else
                # Find parent at previous level
                parent = @level_stack[level - 1]
                if parent
                  parent[:children] << node
                  node[:parent] = parent
                end

                # Update stack
                @level_stack = @level_stack[0..level - 1] + [node]
              end
            end
          end

          def get_indent_size(indent_data)
            return 0 if indent_data.nil?
            return 0 if indent_data.is_a?(Array) && indent_data.empty?

            indent_str = if indent_data.is_a?(Array)
                          indent_data.join('')
                        else
                          indent_data.to_s
                        end

            indent_str.length
          end

          def calculate_relative_level(indent_size, min_indent)
            relative_indent = indent_size - min_indent
            return 0 if relative_indent <= 0

            # Try 2-space indentation first
            level = relative_indent / 2
            # If not evenly divisible, try 4-space
            level = relative_indent / 4 if relative_indent % 2 != 0

            level
          end

          private

          def calculate_level(indent_data)
            # Handle empty array or nil
            return 0 if indent_data.nil?
            return 0 if indent_data.is_a?(Array) && indent_data.empty?

            # Convert to string and count length
            indent_str = if indent_data.is_a?(Array)
                          indent_data.join('')
                        else
                          indent_data.to_s
                        end

            return 0 if indent_str.empty?

            # Count spaces (2 or 4 spaces per level)
            spaces = indent_str.length
            # Try 2-space indentation first
            level = spaces / 2
            # If not evenly divisible, try 4-space
            level = spaces / 4 if spaces % 2 != 0

            level
          end

          def extract_content(node_data)
            return node_data[:content].to_s if node_data[:content]
            ""
          end

          def extract_shape(node_data)
            # Determine shape based on which parser rule matched
            return "circle" if node_data[:shape_circle]
            return "bang" if node_data[:shape_bang]
            return "cloud" if node_data[:shape_cloud]
            return "hexagon" if node_data[:shape_hexagon]
            return "square" if node_data[:shape_square]
            "default"
          end

          def find_parent(level)
            return nil if level == 0
            # Parent is the last node at level - 1
            @level_stack[level - 1]
          end
        end

        # Transform the nodes array into a tree structure
        rule(nodes: subtree(:nodes)) do
          builder = TreeBuilder.new
          nodes_array = Array(nodes)

          nodes_array.each do |node_data|
            next unless node_data.is_a?(Hash)

            # Skip if no actual node data (just whitespace)
            next unless node_data[:content] || node_data[:icon] || node_data[:classes] ||
                       node_data[:shape_circle] || node_data[:shape_bang] ||
                       node_data[:shape_cloud] || node_data[:shape_hexagon] ||
                       node_data[:shape_square]

            builder.add_node(node_data)
          end

          # Finalize to adjust levels and rebuild hierarchy
          builder.finalize

          {
            root: builder.root,
            nodes: builder.all_nodes
          }
        end
      end
    end
  end
end