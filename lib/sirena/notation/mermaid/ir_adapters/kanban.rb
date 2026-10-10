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
            occupied = []
            adapted = adapted_columns(columns, occupied)
            items = items_for(adapted)
            root_id = reserve_id(diagram.id || "kanban", occupied)
            IR::Data.new(
              id: root_id, label: diagram.title, role: "work_board",
              items: items, values: values_for(adapted, occupied)
            )
          end

          def adapted_columns(columns, occupied)
            columns.map do |column|
              column_id = reserve_id(column.id, occupied)
              cards = column.cards.map do |card|
                [card, reserve_id(card.id, occupied)]
              end
              [column, column_id, cards]
            end
          end

          def items_for(columns)
            columns.flat_map do |column, column_id, cards|
              [IR::Item.new(
                id: column_id, label: column.title, role: "board_column",
              )] + cards.map do |card, card_id|
                IR::Item.new(
                  id: card_id, label: card.text, role: "work_item",
                  parent_id: column_id
                )
              end
            end
          end

          def values_for(columns, occupied)
            columns.flat_map do |column, column_id, cards|
              decoration_values(column, column_id, occupied) +
                cards.flat_map do |card, card_id|
                  card_values(card, card_id, occupied)
                end
            end
          end

          def decoration_values(item, parent_id, occupied)
            values = []
            if item.icon
              values << text_value(parent_id, "icon", item.icon, occupied)
            end
            values + item.classes.map do |style|
              text_value(parent_id, "style_reference", style, occupied)
            end
          end

          def card_values(card, parent_id, occupied)
            metadata = card.metadata.map do |name, value|
              text_value(parent_id, METADATA_ROLES.fetch(name), value, occupied)
            end
            metadata + card.classes.map do |style|
              text_value(parent_id, "style_reference", style, occupied)
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
          private_class_method :adapted_columns, :items_for, :values_for,
                               :decoration_values, :card_values, :text_value,
                               :reserve_id
        end
      end
    end
  end
end
