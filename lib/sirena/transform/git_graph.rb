# frozen_string_literal: true

module Sirena
  module Transform
    # Transforms a GitGraph diagram into a positioned layout structure.
    #
    # Unlike other transformers that use ELK layout, GitGraph uses a custom
    # layout algorithm that assigns commits to horizontal lanes (Y positions)
    # and sequential X positions based on commit order.
    #
    # The layout algorithm handles:
    # - Branch lane assignment (main branch at top)
    # - Commit positioning (chronological X coordinates)
    # - Parent-child relationships for drawing connections
    # - Merge point tracking for drawing merge arrows
    # - Cherry-pick visualization
    #
    # @example Transform a git graph
    #   transform = Transform::GitGraph.new
    #   layout = transform.to_graph(diagram)
    class GitGraph
      # Spacing between commits horizontally
      COMMIT_SPACING = 80

      # Spacing between branch lanes vertically
      LANE_SPACING = 60

      # Radius of commit circles
      COMMIT_RADIUS = 8

      # Default branch colors (cycling through these)
      DEFAULT_COLORS = %w[
        #2563eb #7c3aed #db2777 #ea580c #ca8a04
        #16a34a #0891b2 #4f46e5 #c026d3 #dc2626
      ].freeze

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::GitGraph] the git graph diagram
      # @return [Hash] layout data with commits, branches, and connections
      def to_graph(diagram)
        # Build commit lookup and parent tracking
        commits_by_id = build_commit_lookup(diagram.commits)
        branch_info = build_branch_info(diagram)

        # Assign lanes to branches
        lane_assignments = assign_lanes(diagram, branch_info)

        # Position commits
        positioned_commits = position_commits(
          diagram.commits,
          commits_by_id,
          lane_assignments
        )

        # Build connections between commits
        connections = build_connections(
          positioned_commits,
          commits_by_id
        )

        # Build branch metadata
        branches = build_branch_metadata(
          diagram.branches,
          lane_assignments,
          positioned_commits
        )

        {
          commits: positioned_commits,
          branches: branches,
          connections: connections,
          width: calculate_width(positioned_commits),
          height: calculate_height(lane_assignments)
        }
      end

      private

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
          created_at: nil
        }

        # Add other branches
        diagram.branches.each do |branch|
          info[branch.name] = {
            parent: branch.parent_branch || "main",
            order: branch.order || info.size,
            created_at: branch.created_at_commit
          }
        end

        info
      end

      # Assigns lanes (Y positions) to branches.
      #
      # Main branch gets lane 0, child branches get lanes below parent.
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
      # @return [Array<Hash>] positioned commits
      def position_commits(commits, commits_by_id, lane_assignments)
        positioned = []

        commits.each_with_index do |commit, idx|
          # X position is based on commit order
          x = idx * COMMIT_SPACING + COMMIT_SPACING

          # Y position is based on branch lane
          branch = commit.branch_name || "main"
          lane = lane_assignments[branch] || 0
          y = lane * LANE_SPACING + LANE_SPACING

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
            # Store original commit for reference
            original: commit
          }
        end

        positioned
      end

      # Builds connections between commits.
      #
      # @param positioned_commits [Array<Hash>] positioned commits
      # @param commits_by_id [Hash] commit lookup
      # @return [Array<Hash>] connections with from/to commits and type
      def build_connections(positioned_commits, commits_by_id)
        connections = []
        commit_positions = positioned_commits.each_with_object({}) do |c, h|
          h[c[:id]] = c
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
              type: connection_type
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
          color: DEFAULT_COLORS[0]
        }

        # Add other branches with cycling colors
        branches.each_with_index do |branch, idx|
          metadata << {
            name: branch.name,
            lane: lane_assignments[branch.name] || (idx + 1),
            color: DEFAULT_COLORS[(idx + 1) % DEFAULT_COLORS.length]
          }
        end

        metadata
      end

      # Calculates total width needed for the layout.
      #
      # @param positioned_commits [Array<Hash>] positioned commits
      # @return [Numeric] total width in pixels
      def calculate_width(positioned_commits)
        return COMMIT_SPACING * 2 if positioned_commits.empty?

        max_x = positioned_commits.map { |c| c[:x] }.max
        max_x + COMMIT_SPACING
      end

      # Calculates total height needed for the layout.
      #
      # @param lane_assignments [Hash] lane assignments
      # @return [Numeric] total height in pixels
      def calculate_height(lane_assignments)
        return LANE_SPACING * 2 if lane_assignments.empty?

        max_lane = lane_assignments.values.max
        (max_lane + 1) * LANE_SPACING + LANE_SPACING
      end
    end
  end
end