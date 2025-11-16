# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/architecture"

module Sirena
  module Transform
    # Architecture diagram transformer for converting architecture models to positioned layouts
    class ArchitectureTransform < Base
      # Default dimensions
      DEFAULT_SERVICE_WIDTH = 120
      DEFAULT_SERVICE_HEIGHT = 80
      DEFAULT_GROUP_PADDING = 30
      DEFAULT_SPACING = 40
      DEFAULT_ICON_SIZE = 24

      # Converts an architecture diagram to a positioned layout structure
      #
      # @param diagram [Diagram::ArchitectureDiagram] the diagram to transform
      # @return [Hash] positioned layout hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, "Diagram cannot be nil" if diagram.nil?

        # Build hierarchy
        hierarchy = build_hierarchy(diagram)

        # Calculate positions
        service_positions = position_services(diagram, hierarchy)
        group_bounds = calculate_group_bounds(diagram, service_positions)
        edge_positions = position_edges(diagram, service_positions)

        {
          services: service_positions,
          groups: group_bounds,
          edges: edge_positions,
          width: calculate_total_width(service_positions, group_bounds),
          height: calculate_total_height(service_positions, group_bounds),
        }
      end

      private

      def build_hierarchy(diagram)
        hierarchy = {
          groups: {},
          services_by_group: {},
        }

        # Map groups
        diagram.groups.each do |group|
          parent_id = group.parent_id || :root
          hierarchy[:groups][group.id] = {
            group: group,
            parent_id: parent_id,
            children: [],
          }
        end

        # Build parent-child relationships for groups
        diagram.groups.each do |group|
          if group.parent_id && hierarchy[:groups][group.parent_id]
            hierarchy[:groups][group.parent_id][:children] << group.id
          end
        end

        # Map services to groups
        diagram.services.each do |service|
          group_id = service.group_id || :root
          hierarchy[:services_by_group][group_id] ||= []
          hierarchy[:services_by_group][group_id] << service
        end

        hierarchy
      end

      def position_services(diagram, hierarchy)
        positions = {}
        current_x = DEFAULT_SPACING
        current_y = DEFAULT_SPACING

        # Group services by their group
        groups_to_layout = [:root] + diagram.groups.map(&:id)

        groups_to_layout.each do |group_id|
          services = hierarchy[:services_by_group][group_id] || []
          next if services.empty?

          # Position services in this group
          services.each_with_index do |service, index|
            dims = calculate_service_dimensions(service)

            positions[service.id] = {
              service: service,
              x: current_x,
              y: current_y,
              width: dims[:width],
              height: dims[:height],
              group_id: group_id,
            }

            current_x += dims[:width] + DEFAULT_SPACING
          end

          # Move to next row
          current_x = DEFAULT_SPACING
          current_y += DEFAULT_SERVICE_HEIGHT + DEFAULT_SPACING * 2
        end

        # Apply edge-based adjustments if needed
        adjust_positions_for_edges(diagram, positions)

        positions
      end

      def adjust_positions_for_edges(diagram, positions)
        # This is a simple adjustment - could be enhanced with force-directed layout
        diagram.edges.each do |edge|
          from = positions[edge.from_id]
          to = positions[edge.to_id]
          next unless from && to

          # If positions suggest directional hints, try to respect them
          if edge.from_position == "R" && edge.to_position == "L"
            # From should be to the left of to
            if from[:x] > to[:x]
              temp_x = from[:x]
              from[:x] = to[:x]
              to[:x] = temp_x
            end
          elsif edge.from_position == "L" && edge.to_position == "R"
            # From should be to the right of to
            if from[:x] < to[:x]
              temp_x = from[:x]
              from[:x] = to[:x]
              to[:x] = temp_x
            end
          elsif edge.from_position == "T" && edge.to_position == "B"
            # From should be above to
            if from[:y] > to[:y]
              temp_y = from[:y]
              from[:y] = to[:y]
              to[:y] = temp_y
            end
          elsif edge.from_position == "B" && edge.to_position == "T"
            # From should be below to
            if from[:y] < to[:y]
              temp_y = from[:y]
              from[:y] = to[:y]
              to[:y] = temp_y
            end
          end
        end
      end

      def calculate_service_dimensions(service)
        label = service.label || service.id
        label_dims = measure_text(label, font_size: 14)

        width = [label_dims[:width] + 40, DEFAULT_SERVICE_WIDTH].max
        height = DEFAULT_SERVICE_HEIGHT

        {
          width: width,
          height: height,
        }
      end

      def calculate_group_bounds(diagram, service_positions)
        bounds = {}

        diagram.groups.each do |group|
          # Find all services in this group
          group_services = service_positions.values.select do |pos|
            pos[:group_id] == group.id
          end

          # Find all child groups
          child_groups = diagram.groups.select { |g| g.parent_id == group.id }

          if group_services.empty? && child_groups.empty?
            next
          end

          # Calculate bounding box
          if group_services.any?
            min_x = group_services.map { |s| s[:x] }.min
            min_y = group_services.map { |s| s[:y] }.min
            max_x = group_services.map { |s| s[:x] + s[:width] }.max
            max_y = group_services.map { |s| s[:y] + s[:height] }.max
          else
            # Use child group bounds
            min_x = Float::INFINITY
            min_y = Float::INFINITY
            max_x = -Float::INFINITY
            max_y = -Float::INFINITY

            child_groups.each do |child|
              child_bounds = bounds[child.id]
              next unless child_bounds

              min_x = [min_x, child_bounds[:x]].min
              min_y = [min_y, child_bounds[:y]].min
              max_x = [max_x, child_bounds[:x] + child_bounds[:width]].max
              max_y = [max_y, child_bounds[:y] + child_bounds[:height]].max
            end
          end

          bounds[group.id] = {
            group: group,
            x: min_x - DEFAULT_GROUP_PADDING,
            y: min_y - DEFAULT_GROUP_PADDING,
            width: max_x - min_x + DEFAULT_GROUP_PADDING * 2,
            height: max_y - min_y + DEFAULT_GROUP_PADDING * 2,
          }
        end

        bounds
      end

      def position_edges(diagram, service_positions)
        diagram.edges.map do |edge|
          from = service_positions[edge.from_id]
          to = service_positions[edge.to_id]

          next unless from && to

          # Calculate connection points based on position hints
          from_point = calculate_connection_point(from, edge.from_position || "R")
          to_point = calculate_connection_point(to, edge.to_position || "L")

          {
            edge: edge,
            from_x: from_point[:x],
            from_y: from_point[:y],
            to_x: to_point[:x],
            to_y: to_point[:y],
          }
        end.compact
      end

      def calculate_connection_point(service_pos, position)
        case position
        when "L"
          { x: service_pos[:x], y: service_pos[:y] + service_pos[:height] / 2 }
        when "R"
          { x: service_pos[:x] + service_pos[:width], y: service_pos[:y] + service_pos[:height] / 2 }
        when "T"
          { x: service_pos[:x] + service_pos[:width] / 2, y: service_pos[:y] }
        when "B"
          { x: service_pos[:x] + service_pos[:width] / 2, y: service_pos[:y] + service_pos[:height] }
        else
          # Default to right
          { x: service_pos[:x] + service_pos[:width], y: service_pos[:y] + service_pos[:height] / 2 }
        end
      end

      def calculate_total_width(service_positions, group_bounds)
        max_service_x = service_positions.values.map { |s| s[:x] + s[:width] }.max || 0
        max_group_x = group_bounds.values.map { |g| g[:x] + g[:width] }.max || 0

        [max_service_x, max_group_x].max + DEFAULT_SPACING
      end

      def calculate_total_height(service_positions, group_bounds)
        max_service_y = service_positions.values.map { |s| s[:y] + s[:height] }.max || 0
        max_group_y = group_bounds.values.map { |g| g[:y] + g[:height] }.max || 0

        [max_service_y, max_group_y].max + DEFAULT_SPACING
      end
    end
  end
end