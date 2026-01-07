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
      end
    end
  end
end