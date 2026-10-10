# frozen_string_literal: true

require_relative "../klass"
require_relative "../member"
require_relative "../package"

module Sirena
  module Notation
    module PlantUML
      module IRReader
        # Rebuilds the packages, classes and members.
        module Structure
          KINDS = {
            "class" => :class, "abstract_class" => :abstract,
            "interface" => :interface
          }.freeze
          private_constant :KINDS

          module_function

          # @return [Array<Package>]
          def packages(index)
            index.with_role("package").map do |node|
              package(node, index)
            end
          end

          # @return [Array<Klass>]
          def classes(index)
            index.with_role(*KINDS.keys).map { |node| klass(node, index) }
          end

          def package(node, index)
            Package.new(
              id: index.detail(node, "source_id"), title: node.label,
              shape: index.detail(node, "shape").to_sym,
              icon: !index.detail(node, "icon").nil?,
              parent: source_id(node.parent_id, index),
              color: index.detail(node, "color")
            )
          end

          def klass(node, index)
            Klass.new(
              name: node.label, kind: KINDS.fetch(node.role),
              body: members(node, index).freeze,
              package: source_id(node.parent_id, index),
              stereotypes: index.details(node, "stereotype").freeze,
              generics: index.detail(node, "generics"),
              tags: index.details(node, "tag").freeze
            )
          end

          def members(node, index)
            index.children(node, "field", "method").map do |member|
              member(member, index)
            end
          end

          def member(node, index)
            Member.new(
              kind: node.role.to_sym, name: node.label,
              visibility: index.detail(node, "visibility")&.to_sym,
              type: index.detail(node, "type"),
              parameters: index.detail(node, "parameters"),
              modifiers: index.details(node, "modifier").map(&:to_sym).freeze
            )
          end

          def source_id(node_id, index)
            return if node_id.nil?

            index.detail(index.node(node_id), "source_id")
          end
        end
      end
    end
  end
end
