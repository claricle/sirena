# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Timeline model to ordered source placements.
        module Timeline
          module_function

          def call(diagram)
            root_id = diagram.id || "timeline"
            occupied = [root_id]
            items = section_items(diagram.sections, occupied)
            items.concat(event_items(diagram.events, nil, occupied))
            IR::Prepositioned.new(
              id: root_id, label: diagram.title, role: "chronology",
              accessibility_title: diagram.acc_title,
              accessibility_description: diagram.acc_description,
              items: items
            )
          end

          def section_items(sections, occupied)
            sections.flat_map.with_index do |section, index|
              section_id = reserve_id("section_#{index}", occupied)
              section_item = placed_item(
                id: section_id, label: section.name, role: "section",
                dimension: "track", ordinal: index,
                value: IR::Scalar.new(number: index)
              )
              [section_item,
               *event_items(section.events, section_id, occupied),
               *task_items(section.tasks, section_id, occupied)]
            end
          end

          def event_items(events, parent_id, occupied)
            events.flat_map.with_index do |event, index|
              event_id = reserve_id("event_#{index}", occupied)
              event_item = placed_item(
                id: event_id, label: event.time, role: "event",
                parent_id: parent_id, dimension: "time", ordinal: index,
                value: IR::Scalar.new(text: event.time)
              )
              [event_item,
               *description_items(event.descriptions, event_id, occupied)]
            end
          end

          def description_items(descriptions, parent_id, occupied)
            descriptions.map.with_index do |description, index|
              placed_item(
                id: reserve_id("description_#{index}", occupied),
                label: description, role: "description",
                parent_id: parent_id, dimension: "description",
                ordinal: index, value: IR::Scalar.new(number: index)
              )
            end
          end

          def task_items(tasks, parent_id, occupied)
            tasks.map.with_index do |task, index|
              placed_item(
                id: reserve_id("task_#{index}", occupied),
                label: task, role: "task", parent_id: parent_id,
                dimension: "task", ordinal: index,
                value: IR::Scalar.new(number: index)
              )
            end
          end

          def placed_item(attributes)
            placement = IR::Placement.new(
              dimension: attributes.fetch(:dimension),
              ordinal: attributes.fetch(:ordinal),
              value: attributes.fetch(:value),
            )
            IR::PrepositionedItem.new(
              id: attributes.fetch(:id), label: attributes[:label],
              role: attributes.fetch(:role), parent_id: attributes[:parent_id],
              placements: [placement]
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
          private_class_method :section_items, :event_items,
                               :description_items, :task_items, :placed_item,
                               :reserve_id
        end
      end
    end
  end
end
