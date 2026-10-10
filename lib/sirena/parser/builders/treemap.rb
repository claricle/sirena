# frozen_string_literal: true

require "parslet"
require_relative "../../diagram/treemap"

module Sirena
  module Parser
    module Builders
      # Transform for converting treemap parse tree to diagram model
      class Treemap < Parslet::Transform
        rule(number: simple(:x)) { x.to_f }
        rule(string: simple(:x)) { x.to_s }
        rule(string: sequence(:x)) { "" } # Empty string
        rule(identifier: simple(:x)) { x.to_s }

        rule(keyword: simple(:_kw), statements: subtree(:stmts)) do
          {
            type: :treemap,
            statements: Array(stmts).compact,
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
        rule(
          class_def: {
            class_name: simple(:name),
            class_styles: simple(:styles),
          },
        ) do
          {
            type: :class_def,
            name: name.to_s,
            styles: styles.to_s,
          }
        end

        # Transform happens bottom-up, so handle nested parts first
        # Then handle the node structure

        # Node with all fields
        rule(node: subtree(:n)) do
          # An empty indent parses to [], a non-empty one to a string.
          indent_val = n[:indent]
          indent_len = indent_val.is_a?(Array) ? 0 : indent_val.to_s.length

          result = {
            type: :node,
            indent: indent_len,
            label: n[:label],
          }

          result[:value] = n[:value] if n.key?(:value)
          result[:css_class] = n[:css_class].to_s if n.key?(:css_class)

          result
        end

        # Builds Treemap from the intermediate statement list. #apply
        # cannot be overridden to do this: Parslet's transform recurses
        # through it, so it would run on every subtree.
        #
        # @param data [Hash] the `{type: :treemap, statements: [...]}`
        #   hash produced by this class's Parslet rules
        # @return [Diagram::Treemap] the built diagram
        def build_diagram(data)
          diagram = Diagram::Treemap.new
          statements = data[:statements] || []
          nodes = statements.filter_map { |stmt| consume(stmt, diagram) }
          build_hierarchy(diagram, nodes)
          diagram
        end

        private

        def consume(statement, diagram)
          case statement[:type]
          when :title then diagram.title = statement[:value]
          when :class_def then add_class_def(statement, diagram)
          when :acc_title, :acc_descr
            # Accessibility metadata is parsed, not yet stored on the model.
          else
            # Only :node is left: the rules above emit no other type.
            return statement
          end
          nil
        end

        def add_class_def(statement, diagram)
          diagram.add_class_def(statement[:name], statement[:styles])
        end

        # Builds the hierarchical node tree from the flat, indented
        # node list the parse tree produces.
        #
        # @param diagram [Diagram::Treemap] diagram to populate
        # @param nodes [Array<Hash>] flat node statements, in source
        #   order, each carrying its indentation level
        # @return [void]
        def build_hierarchy(diagram, nodes)
          stack = []
          nodes.each do |node_data|
            indent = node_data[:indent] || 0
            node = build_node(node_data)
            stack.pop while stack.any? && stack.last[0] >= indent
            attach_node(diagram, stack, node)
            stack.push([indent, node])
          end
        end

        def build_node(data)
          Diagram::TreemapNode.new(data[:label], data[:value]).tap do |node|
            node.css_class = data[:css_class] if data[:css_class]
          end
        end

        def attach_node(diagram, stack, node)
          return diagram.add_root_node(node) if stack.empty?

          stack.last[1].add_child(node)
        end
      end
    end
  end
end
