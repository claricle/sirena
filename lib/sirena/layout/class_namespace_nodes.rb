# frozen_string_literal: true

require_relative "class_namespace_box"

module Sirena
  module Layout
    # Wraps the class nodes of each namespace in a grid cluster, and turns
    # the placed clusters back into ClassNamespaceBox objects.
    class ClassNamespaceNodes
      # @param size [#call] given a title, returns its { width:, height: }
      def initialize(size:)
        @size = size
      end

      # @param nodes [Array<Hash>] class nodes
      # @param namespaces [Array<#name, #class_ids>]
      # @return [Array<Hash>] the nodes, with each namespace's members
      #   replaced by one cluster at the position of its first member;
      #   a namespace with no members follows as a titled leaf, as mmdc
      #   draws it
      def nest(nodes, namespaces)
        owners = owner_index(nodes, namespaces)
        seen = {}
        nest_members(nodes, owners, seen) + empty_nodes(namespaces, owners)
      end

      def nest_members(nodes, owners, seen)
        nodes.filter_map do |node|
          cluster = owners[node[:id]]
          next node unless cluster
          next if seen.key?(cluster[:id])

          seen[cluster[:id]] = true
          cluster
        end
      end

      # @param nodes [Array<Hash>] nodes as #nest returns them, placed
      # @return [Array(Array<Hash>, Array<ClassNamespaceBox>)] the plain
      #   nodes and the namespace boxes, both in canvas coordinates
      def flatten(nodes)
        plain = []
        boxes = []
        collect(nodes, [0, 0], plain, boxes)
        [plain, boxes]
      end

      private

      def empty_nodes(namespaces, owners)
        placed = owners.values.map { |cluster| cluster[:id] }
        namespaces.filter_map do |item|
          leaf_node(item.name) unless placed.include?("namespace:#{item.name}")
        end
      end

      # mmdc pads the title 32px each side inside a 56px-high box.
      def leaf_node(name)
        label = @size.call(name)
        {
          id: "namespace:#{name}",
          width: label[:width] + 64,
          height: 56,
          metadata: { title: name },
        }
      end

      def owner_index(nodes, namespaces)
        namespaces.each_with_object({}) do |item, index|
          members = unclaimed(nodes, item, index)
          next if members.empty?

          cluster = cluster_node(item.name, members)
          members.each { |node| index[node[:id]] = cluster }
        end
      end

      def unclaimed(nodes, item, index)
        nodes.select do |node|
          item.class_ids.include?(node[:id]) && !index.key?(node[:id])
        end
      end

      def cluster_node(name, members)
        {
          id: "namespace:#{name}",
          children: members,
          labels: [{ text: name }.merge(@size.call(name))],
          metadata: { cluster: true, title: name },
        }
      end

      def collect(nodes, origin, plain, boxes)
        nodes.each do |node|
          x = origin[0] + (node[:x] || 0)
          y = origin[1] + (node[:y] || 0)
          next plain << node.merge(x: x, y: y) unless titled?(node)

          boxes << box(node, x, y)
          collect(Array(node[:children]), [x, y], plain, boxes)
        end
      end

      def titled?(node)
        node[:children] || node.dig(:metadata, :title)
      end

      def box(node, left, top)
        ClassNamespaceBox.new(
          id: node[:id], title: node[:metadata][:title], x: left, y: top,
          width: node[:width], height: node[:height]
        )
      end
    end
  end
end
