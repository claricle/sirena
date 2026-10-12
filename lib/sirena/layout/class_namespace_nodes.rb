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
      def nest(nodes, namespaces, hierarchical: false)
        return flat_nest(nodes, namespaces) unless hierarchical

        clusters, owners = cluster_index(nodes, namespace_specs(namespaces))
        attach_nested_clusters(clusters)
        collapse_empty_clusters(clusters)
        roots = root_clusters(clusters)
        owners.transform_values! do |name|
          clusters.fetch(root_name(name, clusters))
        end
        seen = {}
        nest_members(nodes, owners, seen) + empty_nodes(roots, owners)
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

      def flat_nest(nodes, namespaces)
        owners = flat_owner_index(nodes, namespaces)
        seen = {}
        nest_members(nodes, owners, seen) + flat_empty_nodes(namespaces, owners)
      end

      def flat_empty_nodes(namespaces, owners)
        placed = owners.values.map { |cluster| cluster[:id] }
        namespaces.filter_map do |item|
          next if placed.include?("namespace:#{item.name}")

          leaf_node(item.name, title: item.name)
        end
      end

      def flat_owner_index(nodes, namespaces)
        namespaces.each_with_object({}) do |item, index|
          members = unclaimed(nodes, item.class_ids, index)
          next if members.empty?

          cluster = cluster_node(item.name, members, title: item.name)
          members.each { |node| index[node[:id]] = cluster }
        end
      end

      def empty_nodes(roots, owners)
        placed = owners.values.map { |cluster| cluster[:id] }
        roots.reject { |cluster| placed.include?(cluster[:id]) }
      end

      # mmdc pads the title 32px each side inside a 56px-high box.
      def leaf_node(name, title: title_for(name))
        label = @size.call(title)
        {
          id: "namespace:#{name}",
          width: label[:width] + 64,
          height: 56,
          metadata: { title: title },
        }
      end

      def namespace_specs(namespaces)
        namespaces.each_with_object({}) do |item, specs|
          prefix_names(item.name).each { |name| specs[name] ||= [] }
          specs.fetch(item.name).concat(item.class_ids)
        end
      end

      def prefix_names(name)
        parts = name.split(".")
        parts.each_index.map { |index| parts.first(index + 1).join(".") }
      end

      def cluster_index(nodes, specs)
        owners = {}
        clusters = specs.to_h do |name, class_ids|
          members = unclaimed(nodes, class_ids, owners)
          members.each { |node| owners[node[:id]] = name }
          [name, cluster_node(name, members)]
        end
        [clusters, owners]
      end

      def unclaimed(nodes, class_ids, owners)
        nodes.select do |node|
          class_ids.include?(node[:id]) && !owners.key?(node[:id])
        end
      end

      def cluster_node(name, members, title: title_for(name))
        {
          id: "namespace:#{name}",
          children: members,
          labels: [{ text: title }.merge(@size.call(title))],
          metadata: { cluster: true, title: title },
        }
      end

      def attach_nested_clusters(clusters)
        clusters.each do |name, cluster|
          parent = parent_name(name)
          clusters.fetch(parent)[:children] << cluster if clusters.key?(parent)
        end
      end

      def collapse_empty_clusters(clusters)
        clusters.each do |name, cluster|
          cluster.replace(leaf_node(name)) if cluster[:children].empty?
        end
      end

      def root_clusters(clusters)
        clusters.filter_map do |name, cluster|
          cluster unless clusters.key?(parent_name(name))
        end
      end

      def root_name(name, clusters)
        parent = parent_name(name)
        return name unless clusters.key?(parent)

        root_name(parent, clusters)
      end

      def parent_name(name)
        name.rpartition(".").first
      end

      def title_for(name)
        name.rpartition(".").last
      end

      def collect(nodes, origin, plain, boxes)
        nodes.each do |node|
          x, y = offset(node, origin)
          next plain << node.merge(x: x, y: y) unless titled?(node)

          boxes << box(node, x, y)
          collect(Array(node[:children]), [x, y], plain, boxes)
        end
      end

      def offset(node, origin)
        [origin[0] + (node[:x] || 0), origin[1] + (node[:y] || 0)]
      end

      def titled?(node)
        node[:children] || node.dig(:metadata, :title)
      end

      def box(node, left, top)
        ClassNamespaceBox.new(
          id: node[:id], title: node[:metadata][:title], x: left, y: top,
          width: node[:width], height: node[:height],
          title_x: left + (node[:width] / 2), title_y: top + 22
        )
      end
    end
  end
end
