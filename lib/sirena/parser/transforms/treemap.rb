# frozen_string_literal: true

require 'parslet'
require_relative '../../diagram/treemap'

module Sirena
  module Parser
    module Transforms
      # Transform for converting treemap parse tree to diagram model
      class Treemap < Parslet::Transform
        rule(number: simple(:x)) { x.to_f }
        rule(string: simple(:x)) { x.to_s }
        rule(string: sequence(:x)) { '' }  # Empty string
        rule(identifier: simple(:x)) { x.to_s }

        rule(keyword: simple(:_kw), statements: subtree(:stmts)) do
          {
            type: :treemap,
            statements: Array(stmts).compact
          }
        end

        # Title
        rule(title: simple(:t)) do
          { type: :title, value: t.to_s }
        end

        # Accessibility
        rule(acc_title: simple(:t)) do
          { type: :acc_title, value: t.to_s }
        end

        rule(acc_descr: simple(:d)) do
          { type: :acc_descr, value: d.to_s }
        end

        # Class definition
        rule(class_def: {
          class_name: simple(:name),
          class_styles: simple(:styles)
        }) do
          {
            type: :class_def,
            name: name.to_s,
            styles: styles.to_s
          }
        end

        # Transform happens bottom-up, so handle nested parts first
        # Then handle the node structure

        # Node with all fields
        rule(node: subtree(:n)) do
          indent_val = n[:indent]
          # Handle indent - could be Array (empty), Parslet::Slice, or String
          indent_len = if indent_val.is_a?(Array)
                         indent_val.length  # Empty array = 0
                       elsif indent_val.respond_to?(:to_s)
                         indent_val.to_s.length  # String or Parslet::Slice
                       else
                         0
                       end

          label_val = n[:label]
          label_str = label_val.is_a?(String) ? label_val : label_val.to_s

          result = {
            type: :node,
            indent: indent_len,
            label: label_str
          }

          result[:value] = n[:value] if n.key?(:value)
          result[:css_class] = n[:css_class].to_s if n.key?(:css_class)

          result
        end

        class << self
          # Runs the Parslet transform pass, then builds the typed
          # Diagram::TreemapDiagram from its intermediate statement list.
          #
          # This is the method TreemapParser calls — it is the single
          # entry point that turns a raw parse tree into the diagram
          # model.
          #
          # @param tree [Hash, Array] the raw Parslet parse tree
          # @return [Diagram::TreemapDiagram] the built diagram
          def apply_diagram(tree)
            build_diagram(new.apply(tree))
          end

          private

          # Builds TreemapDiagram from the intermediate statement list.
          #
          # @param data [Hash] the `{type: :treemap, statements: [...]}`
          #   hash produced by this class's Parslet rules
          # @return [Diagram::TreemapDiagram] the built diagram
          def build_diagram(data)
            diagram = Diagram::TreemapDiagram.new

            statements = data[:statements] || []
            nodes = []

            statements.each do |stmt|
              case stmt[:type]
              when :title
                diagram.title = stmt[:value]
              when :acc_title
                # Accessibility title: parsed, not yet stored on the model.
              when :acc_descr
                # Accessibility description: parsed, not yet stored on the model.
              when :class_def
                diagram.add_class_def(stmt[:name], stmt[:styles])
              when :node
                nodes << stmt
              end
            end

            build_hierarchy(diagram, nodes)

            diagram
          end

          # Builds the hierarchical node tree from the flat, indented
          # node list the parse tree produces.
          #
          # @param diagram [Diagram::TreemapDiagram] diagram to populate
          # @param nodes [Array<Hash>] flat node statements, in source
          #   order, each carrying its indentation level
          # @return [void]
          def build_hierarchy(diagram, nodes)
            return if nodes.empty?

            # Stack to track the current parent at each indentation level
            # Format: [[indent_level, node], ...]
            stack = []

            nodes.each do |node_data|
              indent = node_data[:indent] || 0
              label = node_data[:label]
              value = node_data[:value]
              css_class = node_data[:css_class]

              node = Diagram::TreemapNode.new(label, value)
              node.css_class = css_class if css_class

              stack.pop while stack.any? && stack.last[0] >= indent

              if stack.empty?
                diagram.add_root_node(node)
              else
                parent = stack.last[1]
                parent.add_child(node)
              end

              stack.push([indent, node])
            end
          end
        end
      end
    end
  end
end