# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps Mermaid's private Git Graph model to a notation-neutral graph.
        module GitGraph
          COMMIT_FIELDS = %i[
            message type tag branch_name merge_branch cherry_pick_parent
          ].freeze
          BRANCH_FIELDS = %i[order parent_branch created_at_commit].freeze
          private_constant :COMMIT_FIELDS, :BRANCH_FIELDS

          module_function

          def call(diagram)
            occupied = []
            root_id = reserve_id("git_graph", occupied)
            commits, commit_ids = commit_nodes(diagram.commits, occupied)
            branches = branch_nodes(diagram.branches, occupied)
            IR::Graph.new(**graph_attributes(
              diagram, root_id, occupied,
              commits.flatten + branches.flatten,
              edges: parent_edges(diagram.commits, commit_ids, occupied)
            ))
          end

          def graph_attributes(diagram, root_id, occupied, nodes, edges:)
            {
              id: root_id, role: "version_history",
              accessibility_title: diagram.acc_title,
              accessibility_description: diagram.acc_description,
              nodes: [orientation_node(diagram, occupied)] + nodes,
              edges: edges
            }
          end

          def orientation_node(diagram, occupied)
            IR::Node.new(
              id: reserve_id("orientation", occupied),
              label: diagram.orientation, role: "orientation"
            )
          end

          def commit_nodes(commits, occupied)
            ids = []
            groups = commits.map.with_index do |commit, index|
              source_id = commit.id || "commit_#{index}"
              node_id = reserve_id("commit_#{source_id}", occupied)
              ids << node_id
              [IR::Node.new(id: node_id, label: source_id, role: "commit")] +
                commit_semantics(commit, node_id, occupied)
            end
            [groups, ids]
          end

          def commit_semantics(commit, parent_id, occupied)
            values = field_values(commit, COMMIT_FIELDS)
            values.concat(parent_values(commit))
            values.concat(action_values(commit))
            values.map do |role, value|
              semantic_node(parent_id, role, value, occupied)
            end
          end

          def field_values(source, fields)
            fields.filter_map do |field|
              value = source.public_send(field)
              [field.to_s, value] unless value.nil?
            end
          end

          def parent_values(commit)
            commit.parent_ids.map { |id| ["parent_reference", id] }
          end

          def action_values(commit)
            values = []
            values << ["merge_commit", "true"] if commit.is_merge
            if commit.is_cherry_pick
              values << ["cherry_pick_commit", "true"]
            end
            values
          end

          def branch_nodes(branches, occupied)
            branches.map do |branch|
              node_id = reserve_id("branch_#{branch.name}", occupied)
              values = field_values(branch, BRANCH_FIELDS)
              [IR::Node.new(
                id: node_id, label: branch.name, role: "branch",
              )] + values.map do |role, value|
                semantic_node(node_id, role, value, occupied)
              end
            end
          end

          def parent_edges(commits, commit_ids, occupied)
            source_nodes = source_node_index(commits, commit_ids)
            commits.flat_map.with_index do |commit, commit_index|
              commit.parent_ids.filter_map.with_index do |parent_id, edge_index|
                endpoints = [
                  source_nodes[parent_id], commit_ids.fetch(commit_index)
                ]
                parent_edge(
                  commit, [commit_index, edge_index], endpoints, occupied
                )
              end
            end
          end

          def parent_edge(commit, indexes, endpoints, occupied)
            source_id, target_id = endpoints
            return unless source_id

            commit_index, edge_index = indexes
            IR::Edge.new(
              id: reserve_id("parent_#{commit_index}_#{edge_index}", occupied),
              source_id: source_id, target_id: target_id,
              role: edge_role(commit)
            )
          end

          def source_node_index(commits, commit_ids)
            commits.each_with_index.to_h do |commit, index|
              [commit.id || "commit_#{index}", commit_ids.fetch(index)]
            end
          end

          def edge_role(commit)
            return "merge" if commit.is_merge
            return "cherry_pick" if commit.is_cherry_pick

            "parent"
          end

          def semantic_node(parent_id, role, value, occupied)
            IR::Node.new(
              id: reserve_id("#{parent_id}_#{role}", occupied),
              label: value.to_s, role: role, parent_id: parent_id
            )
          end

          def reserve_id(preferred, occupied)
            preferred = preferred.to_s
            preferred = "item" if preferred.empty?
            candidate = preferred
            suffix = 2
            while occupied.include?(candidate)
              candidate = "#{preferred}_#{suffix}"
              suffix += 1
            end
            occupied << candidate
            candidate
          end
          private_class_method :graph_attributes, :orientation_node,
                               :commit_nodes, :commit_semantics,
                               :field_values, :parent_values, :action_values,
                               :branch_nodes, :parent_edges, :parent_edge,
                               :source_node_index, :edge_role, :semantic_node,
                               :reserve_id
        end
      end
    end
  end
end
