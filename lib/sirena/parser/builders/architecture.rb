# frozen_string_literal: true

require_relative "../../diagram/architecture"

module Sirena
  module Parser
    module Builders
      # Transform for architecture diagrams
      class Architecture
        TEXT_ATTRIBUTES = {
          title: :title,
          acc_title: :acc_title,
          acc_descr: :acc_descr,
        }.freeze

        ENTITY_BUILDERS = {
          "group" => %i[groups create_group],
          "service" => %i[services create_service],
          "junction" => %i[junctions create_junction],
        }.freeze

        def apply(tree)
          diagram = Diagram::Architecture.new

          # Process tree
          if tree.is_a?(Array)
            tree.each do |item|
              process_statement(diagram, item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash)
            process_statement(diagram, tree)
          end

          diagram
        end

        private

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)
          return if stmt[:header]

          text_attribute = TEXT_ATTRIBUTES.find { |key, _| stmt[key] }
          return assign_text(diagram, stmt, *text_attribute) if text_attribute
          return diagram.edges << create_edge(stmt) if edge?(stmt)

          add_entity(diagram, stmt)
        end

        def assign_text(diagram, stmt, source, target)
          diagram.public_send("#{target}=", extract_text(stmt[source]))
        end

        def edge?(stmt)
          stmt[:from] && stmt[:to]
        end

        def add_entity(diagram, stmt)
          collection, builder = ENTITY_BUILDERS[extract_text(stmt[:stmt_type])]
          return unless collection

          diagram.public_send(collection) << send(builder, stmt)
        end

        def create_group(data)
          Diagram::Architecture::Group.new.tap do |group|
            assign_attributes(group, data, id: :id, label: :label, icon: :icon)
            assign_reference(group, :parent_id, data[:parent])
          end
        end

        def create_service(data)
          Diagram::Architecture::Service.new.tap do |service|
            assign_attributes(
              service, data, id: :id, label: :label, icon: :icon
            )
            assign_reference(service, :group_id, data[:group])
          end
        end

        def create_junction(data)
          Diagram::Architecture::Junction.new.tap do |junction|
            assign_attributes(junction, data, id: :id)
            assign_reference(junction, :group_id, data[:group])
          end
        end

        def create_edge(data)
          Diagram::Architecture::Edge.new.tap do |edge|
            assign_attributes(
              edge,
              data,
              from_id: :from,
              to_id: :to,
              from_position: :from_pos,
              to_position: :to_pos,
              label: :label,
            )
          end
        end

        def assign_attributes(model, data, attributes)
          attributes.each do |target, source|
            value = data[source]
            model.public_send("#{target}=", extract_text(value)) if value
          end
        end

        def assign_reference(model, target, value)
          return if value.nil? || value.to_s.empty?

          model.public_send("#{target}=", extract_text(value))
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            else
              value.values.first.to_s
            end
          when Array
            # Parslet's `.repeat` (no minimum) yields [] rather than a
            # slice when it matches zero characters, e.g. an empty
            # `accDescr {}` block - treat that the same as no text.
            value.map { |v| extract_text(v) }.join
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
