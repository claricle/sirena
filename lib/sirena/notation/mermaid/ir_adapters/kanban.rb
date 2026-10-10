# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Kanban model to notation-neutral ordered data.
        module Kanban
          METADATA_ROLES = {
            assigned: "assignee",
            ticket: "ticket_reference",
            icon: "icon",
            label: "secondary_label",
            priority: "priority",
          }.freeze
          private_constant :METADATA_ROLES

          module_function

          def call(diagram)
            columns = Array(diagram.columns)
            items = items_for(columns)
            occupied = items.map(&:id)
            root_id = reserve_id(diagram.id || "kanban", occupied)
            IR::Data.new(
              id: root_id, label: diagram.title, role: "work_board",
              items: items, values: values_for(columns, occupied)
            )
          end

          def items_for(columns)
            columns.flat_map do |column|
              [IR::Item.new(
                id: column.id, label: column.title, role: "board_column",
              )] + column.cards.map do |card|
                IR::Item.new(
                  id: card.id, label: card.text, role: "work_item",
                  parent_id: column.id
                )
              end
            end
          end

          def values_for(columns, occupied)
            columns.flat_map do |column|
              decoration_values(column, occupied) +
                column.cards.flat_map { |card| card_values(card, occupied) }
            end
          end

          def decoration_values(item, occupied)
            values = []
            if item.icon
              values << text_value(item.id, "icon", item.icon, occupied)
            end
            values + item.classes.map do |style|
              text_value(item.id, "style_reference", style, occupied)
            end
          end

          def card_values(card, occupied)
            metadata = card.metadata.map do |name, value|
              text_value(card.id, METADATA_ROLES.fetch(name), value, occupied)
            end
            metadata + card.classes.map do |style|
              text_value(card.id, "style_reference", style, occupied)
            end
          end

          def text_value(parent_id, role, text, occupied)
            IR::DataValue.new(
              id: reserve_id("#{parent_id}_#{role}", occupied),
              parent_id: parent_id, role: role,
              value: IR::Scalar.new(text: text)
            )
          end

          def reserve_id(preferred, occupied)
            candidate = preferred
            suffix = 2
            while occupied.include?(candidate)
              candidate = "#{preferred}_#{suffix}"
              suffix += 1
            end
            occupied << candidate
            candidate
          end
          private_class_method :items_for, :values_for, :decoration_values,
                               :card_values, :text_value, :reserve_id
        end
      end
    end
  end
end
