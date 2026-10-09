# frozen_string_literal: true

require_relative "base"

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
        attribute :x, :float
        attribute :y, :float
        attribute :branch, :string
        attribute :lane, :integer
        attribute :type, :string
        attribute :parent_ids, :string, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
      end

      class Branch < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :lane, :integer
        attribute :color, :string
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
        orientation = diagram.orientation

        # Build commit lookup and parent tracking
        commits_by_id = build_commit_lookup(diagram.commits)
        branch_info = build_branch_info(diagram)

        # Assign lanes to branches
        lane_assignments = assign_lanes(diagram, branch_info)

        # Position commits
        positioned_commits = position_commits(
          diagram.commits,
          commits_by_id,
          lane_assignments,
          orientation,
        )

        # Build connections between commits
        connections = build_connections(
          positioned_commits,
          commits_by_id,
        )

        # Build branch metadata
        branches = build_branch_metadata(
          diagram.branches,
          lane_assignments,
          positioned_commits,
        )

        width, height = extents(positioned_commits, lane_assignments,
                                orientation)

        {
          commits: positioned_commits,
          branches: branches,
          connections: connections,
          orientation: orientation,
          width: width,
          height: height,
        }
      end

      private

      def scene(diagram)
        graph = build_graph(diagram)
        labels = label_hashes(graph)
        base_width = graph[:width] + (PADDING * 2)
        spill_left, spill_right = label_spill(labels, base_width)
        shift = PADDING + spill_left
        width = base_width + spill_left + spill_right
        height = graph[:height] + (PADDING * 2)

        Scene.new(
          width: width, height: height,
          view_box: "0 0 #{width.to_f} #{height.to_f}",
          commits: typed_commits(graph, labels, shift),
          branches: typed_branches(graph, labels, shift),
          connections: typed_connections(graph[:connections], shift)
        )
      end

      def label_hashes(graph)
        commit_labels(graph) + branch_labels(graph)
      end

      def commit_labels(graph)
        graph[:commits].flat_map do |commit|
          labels = []
          if commit[:id] && !commit[:id].start_with?("commit_")
            labels << positioned_label(commit[:id], commit, graph[:orientation], "id")
          end
          if commit[:tag]
            labels << positioned_label(commit[:tag], commit, graph[:orientation], "tag")
          end
          labels
        end
      end

      def positioned_label(text, commit, orientation, kind)
        x, y, anchor = label_position(commit[:x], commit[:y], orientation, kind)
        { text: text, x: x + PADDING, y: y + PADDING,
          text_anchor: anchor, kind: kind, branch: commit[:branch],
          owner_id: commit[:id] }
      end

      def label_position(x, y, orientation, kind)
        if %w[TB BT].include?(orientation)
          kind == "tag" ? [x - 14, y + 4, "end"] : [x + 14, y + 4, "start"]
        elsif kind == "tag"
          [x, y - 15, "middle"]
        else
          [x, y + 20, "middle"]
        end
      end

      def branch_labels(graph)
        last_commits = graph[:commits].to_h { |commit| [commit[:branch], commit] }
        last_commits.map do |branch, commit|
          x, y, anchor = branch_label_position(commit[:x], commit[:y],
                                               graph[:orientation])
          { text: branch, x: x + PADDING, y: y + PADDING,
            text_anchor: anchor, kind: "branch", branch: branch }
        end
      end

      def branch_label_position(x, y, orientation)
        case orientation
        when "TB" then [x, y + 24, "middle"]
        when "BT" then [x, y - 16, "middle"]
        else [x + 15, y + 4, "start"]
        end
      end

      def label_spill(labels, width)
        return [0, 0] if labels.empty?

        spans = labels.map { |label| label_span(label) }
        lefts, rights = spans.transpose
        [[-lefts.min, 0].max, [rights.max - width, 0].max]
      end

      def label_span(label)
        width = measure_text(label[:text], font_size: small_font_size)[:width] *
          LABEL_HEADROOM
        share = { "start" => 0.0, "middle" => 0.5, "end" => 1.0 }
          .fetch(label[:text_anchor])
        left = label[:x] - (width * share)
        [left, left + width]
      end

      def typed_commits(graph, labels, shift)
        graph[:commits].map do |commit|
          Commit.new(
            id: commit[:id], x: commit[:x] + shift,
            y: commit[:y] + PADDING, branch: commit[:branch],
            lane: commit[:lane], type: commit[:type],
            parent_ids: commit[:parent_ids],
            labels: typed_labels(labels.select do |label|
              label[:kind] != "branch" && label[:owner_id] == commit[:id]
            end, shift - PADDING)
          )
        end
      end

      def typed_branches(graph, labels, shift)
        graph[:branches].map do |branch|
          geometry = labels.find do |label|
            label[:kind] == "branch" && label[:branch] == branch[:name]
          end
          Branch.new(name: branch[:name], lane: branch[:lane],
                     color: branch[:color],
                     label: typed_label(geometry, shift - PADDING))
        end
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
          geometry = connection.merge(
            from_x: connection[:from_x] + shift,
            from_y: connection[:from_y] + PADDING,
            to_x: connection[:to_x] + shift,
            to_y: connection[:to_y] + PADDING,
          )
          Connection.new(
            source: geometry[:from], target: geometry[:to],
            from_x: geometry[:from_x], from_y: geometry[:from_y],
            to_x: geometry[:to_x], to_y: geometry[:to_y],
            from_branch: geometry[:from_branch],
            to_branch: geometry[:to_branch], type: geometry[:type],
            path: connection_path(geometry)
          )
        end
      end

      def connection_path(connection)
        return straight_path(connection) unless connection[:type] == :merge
        return straight_path(connection) if connection[:from_y] == connection[:to_y]

        control_x = connection[:from_x] +
                    ((connection[:to_x] - connection[:from_x]) * 0.5)
        "M #{connection[:from_x]} #{connection[:from_y]} " \
          "C #{control_x} #{connection[:from_y]}, " \
          "#{control_x} #{connection[:to_y]}, " \
          "#{connection[:to_x]} #{connection[:to_y]}"
      end

      def straight_path(connection)
        "M #{connection[:from_x]} #{connection[:from_y]} " \
          "L #{connection[:to_x]} #{connection[:to_y]}"
      end

      def small_font_size
        theme.typography&.font_size_small ||
          Theme::Registry.get(:default).typography.font_size_small
      end

      # Builds a lookup hash of commits by ID.
      #
      # @param commits [Array<Diagram::GitGraph::Commit>] commits
      # @return [Hash<String, Diagram::GitGraph::Commit>] commit lookup
      def build_commit_lookup(commits)
        lookup = {}
        commits.each_with_index do |commit, idx|
          # Use index as fallback ID if no ID specified
          key = commit.id || "commit_#{idx}"
          lookup[key] = commit
        end
        lookup
      end

      # Builds branch information from diagram.
      #
      # @param diagram [Diagram::GitGraph] diagram
      # @return [Hash] branch info with parent relationships
      def build_branch_info(diagram)
        info = {}

        # Start with main branch
        info["main"] = {
          parent: nil,
          order: 0,
          created_at: nil,
        }

        # Add other branches
        diagram.branches.each do |branch|
          info[branch.name] = {
            parent: branch.parent_branch || "main",
            order: branch.order || info.size,
            created_at: branch.created_at_commit,
          }
        end

        info
      end

      # Assigns lanes (rows for LR, columns for TB/BT) to branches.
      #
      # Main branch gets lane 0, child branches get the following lanes.
      #
      # @param diagram [Diagram::GitGraph] diagram
      # @param branch_info [Hash] branch information
      # @return [Hash<String, Integer>] branch name to lane number
      def assign_lanes(diagram, branch_info)
        lanes = {}
        next_lane = 0

        # Assign main branch to lane 0
        lanes["main"] = next_lane
        next_lane += 1

        # Sort branches by order then by creation
        sorted_branches = diagram.branches.sort_by do |b|
          [branch_info[b.name][:order] || 999, b.name]
        end

        # Assign lanes to other branches
        sorted_branches.each do |branch|
          lanes[branch.name] = next_lane
          next_lane += 1
        end

        lanes
      end

      # Positions commits with X and Y coordinates.
      #
      # @param commits [Array<Diagram::GitGraph::Commit>] commits
      # @param commits_by_id [Hash] commit lookup
      # @param lane_assignments [Hash] branch to lane mapping
      # @param orientation [String] "LR", "TB" or "BT"
      # @return [Array<Hash>] positioned commits
      def position_commits(commits, commits_by_id, lane_assignments,
                           orientation)
        positioned = []

        commits.each_with_index do |commit, idx|
          branch = commit.branch_name || "main"
          lane = lane_assignments[branch] || 0
          x, y = coordinates(
            time_position(idx, commits.size, orientation),
            (lane * LANE_SPACING) + LANE_SPACING,
            orientation,
          )

          commit_id = commit.id || "commit_#{idx}"

          positioned << {
            id: commit_id,
            x: x,
            y: y,
            branch: branch,
            lane: lane,
            type: commit.type || "NORMAL",
            tag: commit.tag,
            parent_ids: commit.parent_ids,
            is_merge: commit.is_merge || false,
            merge_branch: commit.merge_branch,
            is_cherry_pick: commit.is_cherry_pick || false,
            cherry_pick_parent: commit.cherry_pick_parent,
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
      # @param commits_by_id [Hash] commit lookup
      # @return [Array<Hash>] connections with from/to commits and type
      def build_connections(positioned_commits, commits_by_id)
        connections = []
        commit_positions = positioned_commits.to_h do |c|
          [c[:id], c]
        end

        positioned_commits.each do |commit|
          # Connect to parent commits
          commit[:parent_ids].each do |parent_id|
            parent = commit_positions[parent_id]
            next unless parent

            connection_type = if commit[:is_merge]
                                :merge
                              elsif commit[:is_cherry_pick]
                                :cherry_pick
                              else
                                :normal
                              end

            connections << {
              from: parent[:id],
              to: commit[:id],
              from_x: parent[:x],
              from_y: parent[:y],
              to_x: commit[:x],
              to_y: commit[:y],
              from_branch: parent[:branch],
              to_branch: commit[:branch],
              type: connection_type,
            }
          end
        end

        connections
      end

      # Builds branch metadata for rendering.
      #
      # @param branches [Array<Diagram::GitGraph::Branch>] branches
      # @param lane_assignments [Hash] lane assignments
      # @param positioned_commits [Array<Hash>] positioned commits
      # @return [Array<Hash>] branch metadata
      def build_branch_metadata(branches, lane_assignments, positioned_commits)
        metadata = []

        # Add main branch
        metadata << {
          name: "main",
          lane: lane_assignments["main"] || 0,
          color: DEFAULT_COLORS[0],
        }

        # Add other branches with cycling colors
        branches.each_with_index do |branch, idx|
          metadata << {
            name: branch.name,
            lane: lane_assignments[branch.name] || (idx + 1),
            color: DEFAULT_COLORS[(idx + 1) % DEFAULT_COLORS.length],
          }
        end

        metadata
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
