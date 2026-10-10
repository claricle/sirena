# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private User Journey model to a notation-neutral graph.
        module UserJourney
          TASK_ROLE_PREFIX = "journey_task_"
          private_constant :TASK_ROLE_PREFIX

          module_function

          def call(diagram)
            root_id = source_id(diagram.id, "user_journey")
            occupied = [root_id]
            nodes, tasks = nodes_for(diagram.sections, occupied)
            IR::Graph.new(**graph_attributes(
              diagram, root_id, nodes, edges_for(tasks, occupied)
            ))
          end

          def graph_attributes(diagram, root_id, nodes, edges)
            {
              id: root_id, label: diagram.title, role: "customer_journey",
              accessibility_title: optional_value(diagram, :acc_title),
              accessibility_description: accessibility_description(diagram),
              nodes: nodes, edges: edges
            }
          end

          def accessibility_description(diagram)
            optional_value(diagram, :acc_description, :acc_descr)
          end

          def nodes_for(sections, occupied)
            nodes = []
            tasks = []
            sections.each_with_index do |section, section_index|
              append_section(
                section, section_index, nodes, tasks, occupied
              )
            end
            [nodes, tasks]
          end

          def append_section(section, index, nodes, tasks, occupied)
            section_id = reserve_id("section_#{index}", occupied)
            nodes << IR::Node.new(
              id: section_id, label: section.name, role: "journey_section",
            )
            section.tasks.each do |task|
              append_task(task, section_id, nodes, tasks, occupied)
            end
          end

          def append_task(task, section_id, nodes, tasks, occupied)
            node = task_node(task, tasks.length, section_id, occupied)
            nodes << node
            nodes.concat(actor_nodes(task, node.id, occupied))
            tasks << node
          end

          def task_node(task, index, section_id, occupied)
            IR::Node.new(
              id: reserve_id("task_#{index}", occupied),
              label: task.name,
              role: "#{TASK_ROLE_PREFIX}#{task.score_color}",
              parent_id: section_id,
              properties: IR::PropertySet.new(weight: task.score),
            )
          end

          def actor_nodes(task, task_id, occupied)
            task.actors.map.with_index do |actor, index|
              IR::Node.new(
                id: reserve_id("#{task_id}_actor_#{index}", occupied),
                label: actor, role: "journey_actor", parent_id: task_id
              )
            end
          end

          def edges_for(tasks, occupied)
            tasks.each_cons(2).with_index.map do |(source, target), index|
              IR::Edge.new(
                id: reserve_id("flow_#{index}", occupied),
                source_id: source.id, target_id: target.id,
                role: "sequence"
              )
            end
          end

          def source_id(value, fallback)
            value.to_s.empty? ? fallback : value
          end

          def optional_value(source, *names)
            names.each do |name|
              next unless source.respond_to?(name)

              value = source.public_send(name)
              return value unless value.nil?
            end
            nil
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
          private_class_method :graph_attributes, :accessibility_description,
                               :nodes_for, :append_section, :append_task,
                               :task_node, :actor_nodes, :edges_for,
                               :source_id, :optional_value, :reserve_id
        end
      end
    end
  end
end
