# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/class_diagram"
require_relative "../../class_notes"
require_relative "../../class_namespaces"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::ClassDiagram from the native parse tree of the
        # +class_diagram+ entry. The statement nodes have the shape
        # Parslet's have, so the Parslet builder, which owns the model
        # rules, reads them as is; only the list shapes are normalised.
        class ClassDiagram
          # The Parslet builder reads a member's source text back from its
          # capture offsets; the native slices carry the same offsets.
          class Reader < Parser::Builders::ClassDiagram
            private

            def collect_slices(node, slices)
              case node
              when Hash then node.each_value { |v| collect_slices(v, slices) }
              when Array then node.each { |v| collect_slices(v, slices) }
              else slices << node if node.respond_to?(:offset)
              end
            end
          end
          private_constant :Reader

          # @param tree [Hash] native parse tree
          # @param source [String] the text the tree was parsed from
          # @return [Diagram::ClassDiagram]
          def apply(tree, source)
            items = statements(tree)
            diagram = Reader.new.apply(items, source)
            diagram.notes = ClassNotes.collect(items, diagram)
            diagram.namespaces = ClassNamespaces.collect(items, diagram)
            diagram
          end

          private

          def statements(tree)
            head = tree.except(:statements)
            [head, *Text.items(tree[:statements])].map { |item| lists(item) }
          end

          # A single-element repeat is a Hash here, an Array in Parslet.
          def lists(item)
            item.to_h do |key, value|
              [key, list_key?(key) ? Text.items(value) : value]
            end
          end

          def list_key?(key)
            %i[body namespace_body].include?(key)
          end
        end
      end
    end
  end
end
