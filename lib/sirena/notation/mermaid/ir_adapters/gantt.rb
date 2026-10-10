# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps the private Gantt model to ordered scheduling constraints.
        module Gantt
          module_function

          def call(diagram)
            root_id = present_id(diagram.id, "gantt")
            occupied = [root_id]
            settings = settings_item(diagram, occupied)
            entries = task_entries(diagram, occupied)
            IR::Prepositioned.new(
              **root_attributes(diagram, root_id),
              items: document_items(diagram, settings, entries, occupied),
              connections: dependency_edges(entries, occupied),
            )
          end

          def settings_item(diagram, occupied)
            IR::PrepositionedItem.new(
              id: reserve_id("schedule_settings", occupied),
              role: "schedule_settings",
              placements: placements(setting_values(diagram)),
            )
          end

          def setting_values(diagram)
            {
              date_format: diagram.date_format,
              axis_format: diagram.axis_format,
              tick_interval: diagram.tick_interval,
              weekend: diagram.weekend,
              inclusive_end_dates: diagram.inclusive_end_dates,
              today_marker: diagram.today_marker,
            }
          end

          def root_attributes(diagram, root_id)
            {
              id: root_id, label: diagram.title, role: "schedule",
              accessibility_title: optional(diagram, :acc_title),
              accessibility_description: accessibility_description(diagram)
            }
          end

          def document_items(diagram, settings, entries, occupied)
            exclusions = exclusion_items(diagram, settings, occupied)
            scheduled = entries.flat_map { |entry| entry.fetch(:items) }
            [settings, *exclusions, *scheduled]
          end

          def exclusion_items(diagram, settings, occupied)
            diagram.excludes.map.with_index do |exclusion, index|
              IR::PrepositionedItem.new(
                id: reserve_id("exclusion_#{index}", occupied),
                label: exclusion, role: "exclusion", parent_id: settings.id,
                placements: [placement("source_order", index, index)]
              )
            end
          end

          def task_entries(diagram, occupied)
            diagram.sections.map.with_index do |section, index|
              section_entry(section, index, occupied)
            end
          end

          def section_entry(section, index, occupied)
            section_id = reserve_id("section_#{index}", occupied)
            section_item = IR::PrepositionedItem.new(
              id: section_id, label: section.name, role: "section",
              placements: [placement("source_order", index, index)]
            )
            tasks = section.tasks.map.with_index do |task, task_index|
              task_entry(task, task_index, section_id, occupied)
            end
            { items: [section_item, *tasks.flat_map { |entry| entry[:items] }],
              tasks: tasks }
          end

          def task_entry(task, index, section_id, occupied)
            item_id = reserve_id(present_id(task.id, "task_#{index}"), occupied)
            item = IR::PrepositionedItem.new(
              id: item_id, label: task.description, role: "task",
              parent_id: section_id, placements: task_placements(task, index)
            )
            flags = task.tags.map.with_index do |tag, flag_index|
              status_item(tag, flag_index, item_id, occupied)
            end
            { source: task, item: item, items: [item, *flags] }
          end

          def task_placements(task, index)
            values = {
              source_order: index, source_id: task.id,
              start_date: task.start_date, end_date: task.end_date,
              duration: task.duration, after_tasks: task.after_task,
              until_task: task.until_task, click_href: task.click_href,
              click_callback: task.click_callback
            }
            placements(values)
          end

          def status_item(tag, index, task_id, occupied)
            IR::PrepositionedItem.new(
              id: reserve_id("#{task_id}_status_#{index}", occupied),
              label: tag, role: "status_flag", parent_id: task_id,
              placements: [placement("source_order", index, index)]
            )
          end

          def dependency_edges(entries, occupied)
            tasks = entries.flat_map { |entry| entry.fetch(:tasks) }
            by_source_id = tasks.each_with_object({}) do |entry, index|
              source_id = entry.fetch(:source).id
              index[source_id] = entry if source_id
            end
            tasks.flat_map.with_index do |entry, index|
              dependency_edges_for(entry, index, by_source_id, occupied)
            end
          end

          def dependency_edges_for(entry, index, by_source_id, occupied)
            task = entry.fetch(:source)
            after_edges = after_edges_for(
              entry, index, task.after_task, by_source_id, occupied
            )
            until_edge = until_edge_for(
              entry, index, task.until_task, by_source_id, occupied
            )
            until_edge ? after_edges.append(until_edge) : after_edges
          end

          def after_edges_for(entry, index, names, by_source_id, occupied)
            names.to_s.split.filter_map.with_index do |id, offset|
              dependency = by_source_id[id]
              next unless dependency

              dependency_edge(
                edge_attributes("starts_after", index, offset,
                                dependency.fetch(:item), entry.fetch(:item)),
                occupied,
              )
            end
          end

          def until_edge_for(entry, index, name, by_source_id, occupied)
            dependency = by_source_id[name]
            return unless dependency

            dependency_edge(
              edge_attributes("ends_at_start", index, 0,
                              entry.fetch(:item), dependency.fetch(:item)),
              occupied,
            )
          end

          def edge_attributes(role, index, offset, source, target)
            {
              id: "dependency_#{index}_#{offset}", role: role,
              source_id: source.id, target_id: target.id
            }
          end

          def dependency_edge(attributes, occupied)
            IR::Edge.new(
              **attributes,
              id: reserve_id(attributes.fetch(:id), occupied),
            )
          end

          def placements(values)
            values.filter_map.with_index do |(dimension, value), ordinal|
              next if value.nil?

              placement(dimension.to_s, ordinal, value)
            end
          end

          def placement(dimension, ordinal, value)
            IR::Placement.new(
              dimension: dimension, ordinal: ordinal, value: scalar(value),
            )
          end

          def scalar(value)
            if [true, false].include?(value)
              return IR::Scalar.new(boolean: value)
            end
            return IR::Scalar.new(number: value) if value.is_a?(Numeric)

            IR::Scalar.new(text: value.to_s)
          end

          def present_id(value, fallback)
            value.to_s.empty? ? fallback : value
          end

          def optional(object, reader)
            object.public_send(reader) if object.respond_to?(reader)
          end

          def accessibility_description(diagram)
            optional(diagram, :acc_description) || optional(diagram, :acc_descr)
          end

          def reserve_id(preferred, occupied)
            candidate = preferred.to_s
            suffix = 2
            while occupied.include?(candidate)
              candidate = "#{preferred}_#{suffix}"
              suffix += 1
            end
            occupied << candidate
            candidate
          end
          private_class_method :settings_item, :setting_values,
                               :root_attributes, :document_items,
                               :exclusion_items, :task_entries, :section_entry,
                               :task_entry, :task_placements, :status_item,
                               :dependency_edges, :dependency_edges_for,
                               :after_edges_for, :until_edge_for,
                               :edge_attributes, :dependency_edge, :placements,
                               :placement, :scalar, :present_id, :optional,
                               :accessibility_description, :reserve_id
        end
      end
    end
  end
end
