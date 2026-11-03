# frozen_string_literal: true

require_relative "../text"
require_relative "../../../diagram/architecture"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Architecture from the native parse tree of the
        # +architecture+ entry.
        class Architecture
          TEXT_ATTRIBUTES = {
            title: :title=,
            acc_title: :acc_title=,
            acc_descr: :acc_descr=,
          }.freeze

          ENTITIES = {
            "group" => %i[groups group_model],
            "service" => %i[services service_model],
            "junction" => %i[junctions junction_model],
          }.freeze

          EDGE_ATTRIBUTES = {
            from_id: :from, to_id: :to, from_position: :from_pos,
            to_position: :to_pos, label: :label
          }.freeze

          # @param tree [Hash, Array, Parsanol::Slice] native parse tree
          # @return [Diagram::Architecture]
          def apply(tree)
            Diagram::Architecture.new.tap do |diagram|
              Text.items(tree[:statements]).each do |item|
                apply_statement(diagram, item)
              end
            end
          end

          private

          def apply_statement(diagram, item)
            return add_text(diagram, item) if text_statement?(item)
            return diagram.edges << edge_model(item) if item.key?(:from)

            collection, builder = ENTITIES.fetch(item[:stmt_type].to_s)
            diagram.public_send(collection) << send(builder, item)
          end

          def text_statement?(item)
            TEXT_ATTRIBUTES.keys.any? { |name| item.key?(name) }
          end

          def add_text(diagram, item)
            key = TEXT_ATTRIBUTES.keys.find { |name| item.key?(name) }
            diagram.public_send(TEXT_ATTRIBUTES[key], text(item[key]))
          end

          def group_model(data)
            Diagram::Architecture::Group.new.tap do |group|
              assign(group, data, id: :id, label: :label, icon: :icon)
              group.parent_id = text(data[:parent]) if data.key?(:parent)
            end
          end

          def service_model(data)
            Diagram::Architecture::Service.new.tap do |service|
              assign(service, data, id: :id, label: :label, icon: :icon)
              service.group_id = text(data[:group]) if data.key?(:group)
            end
          end

          def junction_model(data)
            Diagram::Architecture::Junction.new.tap do |junction|
              junction.id = text(data[:id])
              junction.group_id = text(data[:group]) if data.key?(:group)
            end
          end

          def edge_model(data)
            Diagram::Architecture::Edge.new.tap do |edge|
              assign(edge, data, EDGE_ATTRIBUTES)
            end
          end

          def assign(model, data, attributes)
            attributes.each do |target, source|
              next unless data.key?(source)

              model.public_send("#{target}=", text(data[source]))
            end
          end

          # A reference or position wraps its capture in a one-key Hash.
          def text(node)
            node = node.values.first if node.is_a?(Hash)
            Text.of(node).strip
          end
        end
      end
    end
  end
end
