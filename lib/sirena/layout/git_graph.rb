# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/git_graph"

module Sirena
  module Layout
    # Transforms a GitGraph diagram into a positioned layout structure.
    #
    # Unlike other transformers that use ELK layout, GitGraph uses a custom
    # layout algorithm that assigns commits to lanes and sequential
    # positions along the time axis based on commit order. The time axis
    # runs left to right for `LR`, top to bottom for `TB` and bottom to top
    # for `BT`; lanes are rows for `LR` and columns otherwise.
    #
    # The layout algorithm handles:
    # - Branch lane assignment (main branch in the first lane)
    # - Commit positioning (chronological, along the time axis)
    # - Parent-child relationships for drawing connections
    # - Merge point tracking for drawing merge arrows
    # - Cherry-pick visualization
    #
    # @example Transform a git graph
    #   transform = Layout::GitGraph.new
    #   layout = transform.to_graph(diagram)
    class GitGraph < Base
      # Spacing between commits along the time axis
      COMMIT_SPACING = 80

      # Spacing between branch lanes
      LANE_SPACING = 60

      # Radius of commit circles
      COMMIT_RADIUS = 8

      # Default branch colors (cycling through these)
      DEFAULT_COLORS = %w[
        #2563eb #7c3aed #db2777 #ea580c #ca8a04
        #16a34a #0891b2 #4f46e5 #c026d3 #dc2626
      ].freeze

      PADDING = 40
      LABEL_HEADROOM = 1.2

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :text_anchor, :string
        attribute :kind, :string
        attribute :branch, :string
        attribute :font_size, :float
      end

      class Commit < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :message, :string
        attribute :x, :float
        attribute :y, :float
        attribute :branch, :string
        attribute :lane, :integer
        attribute :type, :string
        attribute :tag, :string
        attribute :parent_ids, :string, collection: true, default: -> { [] }
        attribute :is_merge, :boolean
        attribute :merge_branch, :string
        attribute :is_cherry_pick, :boolean
        attribute :cherry_pick_parent, :string
        attribute :labels, Label, collection: true, default: -> { [] }
      end

      class Branch < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :lane, :integer
        attribute :color, :string
        attribute :order, :integer
        attribute :parent_branch, :string
        attribute :created_at_commit, :string
        attribute :label, Label
      end

      class Connection < Lutaml::Model::Serializable
        attribute :source, :string
        attribute :target, :string
        attribute :from_x, :float
        attribute :from_y, :float
        attribute :to_x, :float
        attribute :to_y, :float
        attribute :from_branch, :string
        attribute :to_branch, :string
        attribute :type, :symbol
        attribute :path, :string
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :commits, Commit, collection: true, default: -> { [] }
        attribute :branches, Branch, collection: true, default: -> { [] }
        attribute :connections, Connection, collection: true,
                                            default: -> { [] }
      end

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::GitGraph] the git graph diagram
      # @return [Hash] layout data with commits, branches, and connections
      def build_graph(diagram)
        graph = ir_graph(diagram)
        orientation = graph_orientation(graph)
        branches = source_branches(graph)
        lane_assignments = assign_lanes(
          branches, build_branch_info(branches)
        )
        commits = position_commits(
          source_commits(graph), lane_assignments, orientation
        )
        graph_result(graph, commits, branches, lane_assignments, orientation)
      end

      private

      def graph_result(graph, commits, branches, lanes, orientation)
        width, height = extents(commits, lanes, orientation)
        {
          commits: commits,
          branches: build_branch_metadata(branches, lanes),
          connections: build_connections(commits, graph.edges),
          orientation: orientation,
          width: width,
          height: height,
        }
      end

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::GitGraph.call(diagram)
      end

      def graph_orientation(graph)
        graph.nodes.find { |node| node.role == "orientation" }&.label || "LR"
      end

      def source_commits(graph)
        children = graph.nodes.group_by(&:parent_id)
        graph.nodes.select { |node| node.role == "commit" }.map do |node|
          commit_attributes(node, children.fetch(node.id, []))
        end
      end

      def commit_attributes(node, semantics)
        commit_identity(node, semantics).merge(commit_action(semantics))
      end

      def commit_identity(node, semantics)
        {
          ir_id: node.id, id: node.label,
          message: semantic_value(semantics, "message"),
          type: semantic_value(semantics, "type") || "NORMAL",
          tag: semantic_value(semantics, "tag"),
          branch_name: semantic_value(semantics, "branch_name"),
          parent_ids: semantic_values(semantics, "parent_reference")
        }
      end

      def commit_action(semantics)
        {
          is_merge: semantic?(semantics, "merge_commit"),
          merge_branch: semantic_value(semantics, "merge_branch"),
          is_cherry_pick: semantic?(semantics, "cherry_pick_commit"),
          cherry_pick_parent: semantic_value(
            semantics, "cherry_pick_parent"
          ),
        }
      end

      def source_branches(graph)
        children = graph.nodes.group_by(&:parent_id)
        graph.nodes.select { |node| node.role == "branch" }.map do |node|
          branch_attributes(node, children.fetch(node.id, []))
        end
      end

      def branch_attributes(node, semantics)
        order = semantic_value(semantics, "order")
        {
          name: node.label, order: order&.to_i,
          parent_branch: semantic_value(semantics, "parent_branch"),
          created_at_commit: semantic_value(semantics, "created_at_commit")
        }
      end

      def semantic_values(semantics, role)
        semantics.select { |node| node.role == role }.map(&:label)
      end

      def semantic_value(semantics, role)
        semantics.find { |node| node.role == role }&.label
      end

      def semantic?(semantics, role)
        semantics.any? { |node| node.role == role }
      end

      def scene(diagram)
        graph = build_graph(diagram)
        labels = label_hashes(graph)
        shift, width, height = scene_dimensions(graph, labels)
        Scene.new(
          width: width, height: height,
          view_box: "0 0 #{width.to_f} #{height.to_f}",
          commits: typed_commits(graph, labels, shift),
          branches: typed_branches(graph, labels, shift),
          connections: typed_connections(graph[:connections], shift)
        )
      end

      def scene_dimensions(graph, labels)
        base_width = graph[:width] + (PADDING * 2)
        spill_left, spill_right = label_spill(labels, base_width)
        shift = PADDING + spill_left
        width = base_width + spill_left + spill_right
        height = graph[:height] + (PADDING * 2)
        [shift, width, height]
      end

      def label_hashes(graph)
        commit_labels(graph) + branch_labels(graph)
      end

      def commit_labels(graph)
        graph[:commits].flat_map do |commit|
          labels_for_commit(commit, graph[:orientation])
        end
      end

      def labels_for_commit(commit, orientation)
        labels = []
        if commit[:id] && !commit[:id].start_with?("commit_")
          labels << positioned_label(commit[:id], commit, orientation, "id")
        end
        if commit[:tag]
          labels << positioned_label(commit[:tag], commit, orientation, "tag")
        end
        labels
      end

      def positioned_label(text, commit, orientation, kind)
        x, y, anchor = label_position(commit[:x], commit[:y], orientation, kind)
        { text: text, x: x + PADDING, y: y + PADDING,
          text_anchor: anchor, kind: kind, branch: commit[:branch],
          owner_id: commit[:id] }
      end

      def label_position(x_coordinate, y_coordinate, orientation, kind)
        if %w[TB BT].include?(orientation)
          vertical_label_position(x_coordinate, y_coordinate, kind)
        elsif kind == "tag"
          [x_coordinate, y_coordinate - 15, "middle"]
        else
          [x_coordinate, y_coordinate + 20, "middle"]
        end
      end

      def vertical_label_position(x_coordinate, y_coordinate, kind)
        return [x_coordinate - 14, y_coordinate + 4, "end"] if kind == "tag"

        [x_coordinate + 14, y_coordinate + 4, "start"]
      end

      def branch_labels(graph)
        last_commits = graph[:commits].to_h do |commit|
          [commit[:branch], commit]
        end
        last_commits.map do |branch, commit|
          branch_label(branch, commit, graph[:orientation])
        end
      end

      def branch_label(branch, commit, orientation)
        x_coordinate, y_coordinate, anchor = branch_label_position(
          commit[:x], commit[:y], orientation
        )
        { text: branch, x: x_coordinate + PADDING,
          y: y_coordinate + PADDING, text_anchor: anchor,
          kind: "branch", branch: branch }
      end

      def branch_label_position(x_coordinate, y_coordinate, orientation)
        case orientation
        when "TB" then [x_coordinate, y_coordinate + 24, "middle"]
        when "BT" then [x_coordinate, y_coordinate - 16, "middle"]
        else [x_coordinate + 15, y_coordinate + 4, "start"]
        end
      end

      def label_spill(labels, width)
        return [0, 0] if labels.empty?

        spans = labels.map { |label| label_span(label) }
        lefts, rights = spans.transpose
        [[-lefts.min, 0].max, [rights.max - width, 0].max]
      end

      def label_span(label)
        width = measure_text(
          label[:text], font_size: small_font_size
        )[:width] * LABEL_HEADROOM
        share = { "start" => 0.0, "middle" => 0.5, "end" => 1.0 }
          .fetch(label[:text_anchor])
        left = label[:x] - (width * share)
        [left, left + width]
      end

      def typed_commits(graph, labels, shift)
        graph[:commits].map do |commit|
          typed_commit(commit, labels, shift)
        end
      end

      def typed_commit(commit, labels, shift)
        Commit.new(
          **typed_commit_attributes(commit, shift),
          labels: typed_labels(
            commit_labels_for(labels, commit), shift - PADDING
          ),
        )
      end

      def typed_commit_attributes(commit, shift)
        typed_commit_identity(commit, shift).merge(
          is_merge: commit[:is_merge], merge_branch: commit[:merge_branch],
          is_cherry_pick: commit[:is_cherry_pick],
          cherry_pick_parent: commit[:cherry_pick_parent]
        )
      end

      def typed_commit_identity(commit, shift)
        {
          id: commit[:id], message: commit[:message],
          x: commit[:x] + shift, y: commit[:y] + PADDING,
          branch: commit[:branch], lane: commit[:lane], type: commit[:type],
          tag: commit[:tag], parent_ids: commit[:parent_ids]
        }
      end

      def commit_labels_for(labels, commit)
        labels.select do |label|
          label[:kind] != "branch" && label[:owner_id] == commit[:id]
        end
      end

      def typed_branches(graph, labels, shift)
        graph[:branches].map do |branch|
          typed_branch(branch, labels, shift)
        end
      end

      def typed_branch(branch, labels, shift)
        geometry = labels.find do |label|
          label[:kind] == "branch" && label[:branch] == branch[:name]
        end
        Branch.new(
          name: branch[:name], lane: branch[:lane], color: branch[:color],
          order: branch[:order], parent_branch: branch[:parent_branch],
          created_at_commit: branch[:created_at_commit],
          label: typed_label(geometry, shift - PADDING)
        )
      end

      def typed_labels(labels, extra_shift)
        labels.map { |label| typed_label(label, extra_shift) }
      end

      def typed_label(label, extra_shift)
        return unless label

        Label.new(text: label[:text], x: label[:x] + extra_shift,
                  y: label[:y], text_anchor: label[:text_anchor],
                  kind: label[:kind], branch: label[:branch],
                  font_size: small_font_size)
      end

      def typed_connections(connections, shift)
        connections.map do |connection|
          typed_connection(connection_geometry(connection, shift))
        end
      end

      def connection_geometry(connection, shift)
        connection.merge(
          from_x: connection[:from_x] + shift,
          from_y: connection[:from_y] + PADDING,
          to_x: connection[:to_x] + shift,
          to_y: connection[:to_y] + PADDING,
        )
      end

      def typed_connection(geometry)
        Connection.new(
          source: geometry[:from], target: geometry[:to],
          from_x: geometry[:from_x], from_y: geometry[:from_y],
          to_x: geometry[:to_x], to_y: geometry[:to_y],
          from_branch: geometry[:from_branch],
          to_branch: geometry[:to_branch], type: geometry[:type],
          path: connection_path(geometry)
        )
      end

      def connection_path(connection)
        return straight_path(connection) unless connection[:type] == :merge
        return straight_path(connection) if same_row?(connection)

        coordinates = connection.values_at(:from_x, :from_y, :to_x, :to_y)
        curved_path(*coordinates)
      end

      def same_row?(connection)
        connection[:from_y] == connection[:to_y]
      end

      def curved_path(from_x, from_y, to_x, to_y)
        control_x = from_x + ((to_x - from_x) * 0.5)
        "M #{from_x} #{from_y} C #{control_x} #{from_y}, " \
          "#{control_x} #{to_y}, #{to_x} #{to_y}"
      end

      def straight_path(connection)
        "M #{connection[:from_x]} #{connection[:from_y]} " \
          "L #{connection[:to_x]} #{connection[:to_y]}"
      end

      def small_font_size
        theme.typography&.font_size_small ||
          Theme::Registry.get(:default).typography.font_size_small
      end

      # Builds branch information from the shared graph's branch entries.
      #
      # @param branches [Array<Hash>] ordered branch semantics
      # @return [Hash] branch info with parent relationships
      def build_branch_info(branches)
        info = {}

        # Start with main branch
        info["main"] = {
          parent: nil,
          order: 0,
          created_at: nil,
        }

        # Add other branches
        branches.each do |branch|
          info[branch[:name]] = {
            parent: branch[:parent_branch] || "main",
            order: branch[:order] || info.size,
            created_at: branch[:created_at_commit],
          }
        end

        info
      end

      # Assigns lanes (rows for LR, columns for TB/BT) to branches.
      #
      # Main branch gets lane 0, child branches get the following lanes.
      #
      # @param branches [Array<Hash>] ordered branch semantics
      # @param branch_info [Hash] branch information
      # @return [Hash<String, Integer>] branch name to lane number
      def assign_lanes(branches, branch_info)
        lanes = {}
        next_lane = 0

        # Assign main branch to lane 0
        lanes["main"] = next_lane
        next_lane += 1

        # Sort branches by order then by creation
        sorted_branches = branches.sort_by do |branch|
          [branch_info[branch[:name]][:order] || 999, branch[:name]]
        end

        # Assign lanes to other branches
        sorted_branches.each do |branch|
          lanes[branch[:name]] = next_lane
          next_lane += 1
        end

        lanes
      end

      # Positions commits with X and Y coordinates.
      #
      # @param commits [Array<Hash>] ordered commit semantics
      # @param lane_assignments [Hash] branch to lane mapping
      # @param orientation [String] "LR", "TB" or "BT"
      # @return [Array<Hash>] positioned commits
      def position_commits(commits, lane_assignments, orientation)
        positioned = []

        commits.each_with_index do |commit, idx|
          branch = commit[:branch_name] || "main"
          lane = lane_assignments[branch] || 0
          x, y = coordinates(
            time_position(idx, commits.size, orientation),
            (lane * LANE_SPACING) + LANE_SPACING,
            orientation,
          )

          commit_id = commit[:id] || "commit_#{idx}"

          positioned << {
            ir_id: commit[:ir_id],
            id: commit_id,
            x: x,
            y: y,
            branch: branch,
            lane: lane,
            message: commit[:message],
            type: commit[:type] || "NORMAL",
            tag: commit[:tag],
            parent_ids: commit[:parent_ids],
            is_merge: commit[:is_merge] || false,
            merge_branch: commit[:merge_branch],
            is_cherry_pick: commit[:is_cherry_pick] || false,
            cherry_pick_parent: commit[:cherry_pick_parent],
          }
        end

        positioned
      end

      # Width and height: the time axis is horizontal for `LR` only.
      def extents(positioned_commits, lane_assignments, orientation)
        time_span = calculate_time_span(positioned_commits.size)
        lane_span = calculate_lane_span(lane_assignments)
        vertical?(orientation) ? [lane_span, time_span] : [time_span, lane_span]
      end

      def vertical?(orientation)
        %w[TB BT].include?(orientation)
      end

      # Distance along the time axis from the start edge of the diagram.
      # `BT` counts down from the last commit, so the first commit is
      # the lowest one.
      def time_position(idx, count, orientation)
        step = orientation == "BT" ? count - idx : idx + 1
        step * COMMIT_SPACING
      end

      def coordinates(time, lane, orientation)
        vertical?(orientation) ? [lane, time] : [time, lane]
      end

      # Builds connections between commits.
      #
      # @param positioned_commits [Array<Hash>] positioned commits
      # @param edges [Array<IR::Edge>] resolved parent connections
      # @return [Array<Hash>] connections with from/to commits and type
      def build_connections(positioned_commits, edges)
        commit_positions = positioned_commits.to_h do |c|
          [c[:ir_id], c]
        end

        edges.filter_map do |edge|
          parent = commit_positions[edge.source_id]
          commit = commit_positions[edge.target_id]
          next unless parent && commit

          {
            from: parent[:id],
            to: commit[:id],
            from_x: parent[:x],
            from_y: parent[:y],
            to_x: commit[:x],
            to_y: commit[:y],
            from_branch: parent[:branch],
            to_branch: commit[:branch],
            type: edge.role == "parent" ? :normal : edge.role.to_sym,
          }
        end
      end

      # Builds branch metadata for rendering.
      #
      # @param branches [Array<Hash>] ordered branch semantics
      # @param lane_assignments [Hash] lane assignments
      # @return [Array<Hash>] branch metadata
      def build_branch_metadata(branches, lane_assignments)
        metadata = []

        # Add main branch
        metadata << {
          name: "main",
          lane: lane_assignments["main"] || 0,
          color: DEFAULT_COLORS[0],
        }

        # Add other branches with cycling colors
        branches.each_with_index do |branch, idx|
          metadata << branch_metadata(branch, idx, lane_assignments)
        end

        metadata
      end

      def branch_metadata(branch, index, lane_assignments)
        {
          name: branch[:name],
          lane: lane_assignments[branch[:name]] || (index + 1),
          color: DEFAULT_COLORS[(index + 1) % DEFAULT_COLORS.length],
          order: branch[:order], parent_branch: branch[:parent_branch],
          created_at_commit: branch[:created_at_commit]
        }
      end

      # Calculates the extent along the time axis.
      #
      # @param commit_count [Integer] number of commits
      # @return [Numeric] extent in pixels
      def calculate_time_span(commit_count)
        return COMMIT_SPACING * 2 if commit_count.zero?

        (commit_count + 1) * COMMIT_SPACING
      end

      # Calculates the extent across the lanes.
      #
      # @param lane_assignments [Hash] lane assignments
      # @return [Numeric] extent in pixels
      def calculate_lane_span(lane_assignments)
        return LANE_SPACING * 2 if lane_assignments.empty?

        max_lane = lane_assignments.values.max
        (max_lane + 1) * LANE_SPACING + LANE_SPACING
      end
    end
  end
end
