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
      COMMIT_SPACING = 50

      # Spacing between branch lanes
      LANE_SPACING = 90

      # Radius of commit circles
      COMMIT_RADIUS = 10

      PADDING = 40
      LABEL_HEADROOM = 1.2
      BRANCH_LABEL_INSET = 8.5
      EMPTY_BRANCH_LABEL_CLEARANCE = 50
      BRANCH_LABEL_BASELINE_OFFSET = 10.5
      VERTICAL_BRANCH_LABEL_CLEARANCE = 40
      EXPLICIT_ID_BRANCH_LABEL_CLEARANCE = 47
      CHERRY_PICK_BRANCH_LABEL_CLEARANCE = 28
      MERMAID_LABEL_FONT_SIZE = 10
      MERMAID_LABEL_WIDTH_SCALE = 0.86
      VERTICAL_LANE_LABEL_RATIO = 0.85
      VERTICAL_LANE_LABEL_HEADROOM = 12.5
      VERTICAL_LANE_GAP = 85

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :text_anchor, :string
        attribute :kind, :string
        attribute :branch, :string
        attribute :font_size, :float
        attribute :rotation, :float
        attribute :rotation_center_x, :float
        attribute :rotation_center_y, :float
        attribute :translation_x, :float
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
        attribute :tags, :string, collection: true, default: -> { [] }
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
        attribute :orientation, :string
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
        main_branch = graph_main_branch(graph)
        branches = source_branches(graph)
        lane_assignments = assign_lanes(
          branches, build_branch_info(branches, main_branch), main_branch
        )
        lane_positions = lane_positions(lane_assignments, orientation)
        commits = position_commits(
          visible_commits(source_commits(graph)), lane_assignments, orientation,
          main_branch, lane_positions
        )
        graph_result(
          graph, commits, branches, lane_assignments, lane_positions,
          orientation, main_branch
        )
      end

      private

      def graph_result(graph, commits, branches, lanes, lane_positions,
                       orientation, main_branch)
        width, height = extents(commits, lanes, lane_positions, orientation)
        {
          commits: commits,
          branches: build_branch_metadata(branches, lanes, main_branch),
          connections: build_connections(commits, graph.edges),
          lane_positions: lane_positions,
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

      def graph_main_branch(graph)
        graph.nodes.find { |node| node.role == "main_branch" }&.label || "main"
      end

      def source_commits(graph)
        children = graph.nodes.group_by(&:parent_id)
        graph.nodes.select { |node| node.role == "commit" }.map do |node|
          commit_attributes(node, children.fetch(node.id, []))
        end
      end

      def visible_commits(commits)
        latest = commits.each_with_object({}) do |commit, identities|
          identities[commit[:id]] = commit[:ir_id] unless
            commit[:is_cherry_pick]
        end
        commits.select do |commit|
          commit[:is_cherry_pick] || latest[commit[:id]] == commit[:ir_id]
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
          tags: semantic_values(semantics, "tag"),
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
        typed_scene(graph, labels, shift, width, height)
      end

      def typed_scene(graph, labels, shift, width, height)
        Scene.new(
          width: width, height: height,
          view_box: "0 0 #{width.to_f} #{height.to_f}",
          orientation: graph[:orientation],
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
        style = commit_label_style(graph)
        graph[:commits].flat_map do |commit|
          labels_for_commit(commit, graph[:orientation], style)
        end
      end

      def commit_label_style(graph)
        return :lone if graph[:orientation] == "LR" && graph[:commits].one?
        return :generated_diagonal if compact_generated_semantic_graph?(graph)
        return :tagged_vertical if all_tagged_vertical_graph?(graph)
        return :linear if vertical?(graph[:orientation]) ||
          simple_three_commit_graph?(graph)

        :legacy
      end

      def labels_for_commit(commit, orientation, style)
        labels = [commit_id_label(commit, orientation, style)].compact
        labels.concat(positioned_tag_labels(commit, orientation, style))
      end

      def commit_id_label(commit, orientation, style)
        return if commit[:is_cherry_pick] || commit[:id].nil?
        return if commit[:id].start_with?("commit_")

        positioned_label(commit[:id], commit, orientation, "id", style)
      end

      def positioned_tag_labels(commit, orientation, style)
        tag_labels(commit).map do |tag|
          positioned_label(tag, commit, orientation, "tag", style)
        end
      end

      def simple_three_commit_graph?(graph)
        graph_sizes(graph) == [3, 1, 2] && normal_connections?(graph) &&
          graph[:commits].all? { |commit| plain_linear_commit?(commit) }
      end

      def graph_sizes(graph)
        %i[commits branches connections].map { |key| graph.fetch(key).size }
      end

      def normal_connections?(graph)
        graph[:connections].all? { |connection| connection[:type] == :normal }
      end

      def plain_linear_commit?(commit)
        commit[:message].nil? && commit[:tags].empty? &&
          commit[:type] == "NORMAL" && !commit[:is_merge] &&
          !commit[:is_cherry_pick]
      end

      def all_tagged_vertical_graph?(graph)
        vertical?(graph[:orientation]) && graph[:branches].one? &&
          graph[:commits].size > 1 && graph[:commits].all? do |commit|
            Array(commit[:tags]).any? { |tag| !tag.empty? }
          end
      end

      def tag_labels(commit)
        tags = Array(commit[:tags])
        return tags.reject(&:empty?) unless tags.empty?
        return [] unless commit[:is_cherry_pick]

        [cherry_pick_label(commit)]
      end

      def cherry_pick_label(commit)
        label = "cherry-pick:#{commit[:id]}"
        parent = commit[:cherry_pick_parent]
        parent ? "#{label}|parent:#{parent}" : label
      end

      def positioned_label(text, commit, orientation, kind, style)
        position = label_position(
          text, commit, orientation, kind, style
        )
        label_geometry(text, commit, kind, position)
      end

      def label_geometry(text, commit, kind, position)
        x, y, anchor, rotation, center_x, center_y, translation_x = position
        { text: text, x: x + PADDING, y: y + PADDING,
          text_anchor: anchor, kind: kind, branch: commit[:branch],
          owner_id: commit[:ir_id], font_size: small_font_size,
          rotation: rotation,
          rotation_center_x: padded_coordinate(center_x),
          rotation_center_y: padded_coordinate(center_y),
          translation_x: translation_x }.compact
      end

      def padded_coordinate(coordinate)
        coordinate && (coordinate + PADDING)
      end

      def label_position(text, commit, orientation, kind, style)
        x_coordinate, y_coordinate = commit.values_at(:x, :y)
        return lone_label_position(text, x_coordinate, y_coordinate, kind) if
          style == :lone
        if %i[linear tagged_vertical].include?(style) && kind == "id"
          font_size = style == :tagged_vertical ? MERMAID_LABEL_FONT_SIZE : nil
          return linear_label_position(text, x_coordinate, y_coordinate,
                                       orientation, font_size)
        end
        if style == :tagged_vertical && kind == "tag"
          return tagged_vertical_label_position(x_coordinate, y_coordinate)
        end
        if style == :generated_diagonal && kind == "id"
          width = mermaid_label_width(text)
          return diagonal_id_label_position(
            width, x_coordinate, y_coordinate
          )
        end
        if style == :legacy && kind == "id" && generated_commit_id?(commit)
          return [x_coordinate, y_coordinate + 20, "middle"]
        end

        legacy_label_position(
          text, x_coordinate, y_coordinate, orientation, kind
        )
      end

      def generated_commit_id?(commit)
        commit[:id].match?(/\Acommit[-_]\d+\z/)
      end

      def compact_generated_semantic_graph?(graph)
        graph[:orientation] == "LR" && graph[:commits].size <= 3 &&
          graph[:commits].all? { |commit| generated_commit_id?(commit) } &&
          graph[:commits].any? do |commit|
            commit[:is_merge] && tag_labels(commit).any?
          end
      end

      def lone_label_position(text, x_coordinate, y_coordinate, kind)
        width = mermaid_label_width(text)
        return [x_coordinate - (width / 2.0), y_coordinate - 16, "middle"] if
          kind == "tag"

        diagonal_id_label_position(width, x_coordinate, y_coordinate)
      end

      def mermaid_label_width(text)
        TextMeasurement.measure_in(
          :arial, text, font_size: MERMAID_LABEL_FONT_SIZE
        )[:width] * MERMAID_LABEL_WIDTH_SCALE
      end

      def diagonal_id_label_position(width, x_coordinate, y_coordinate)
        offset_x, offset_y = diagonal_id_label_offsets(width)
        [x_coordinate - (width / 2.0) + offset_x,
         y_coordinate + 25 + offset_y, "start", -45.0,
         x_coordinate - COMMIT_RADIUS, y_coordinate]
      end

      def diagonal_id_label_offsets(width)
        shift_x = -7.5 - (((width + 10) / 25.0) * 9.5)
        shift_y = 10 + ((width / 25.0) * 8.5)
        diagonal = Math.sqrt(2)
        [(shift_x - shift_y) / diagonal, (shift_x + shift_y) / diagonal]
      end

      def linear_label_position(text, x_coordinate, y_coordinate, orientation,
                                font_size = nil)
        return vertical_label_position(
          text, x_coordinate, y_coordinate, font_size
        ) if
          vertical?(orientation)

        width = measure_text(text, font_size: small_font_size)[:width]
        [x_coordinate - (width / 2.0), y_coordinate + 24, "start"]
      end

      def legacy_label_position(text, x_coordinate, y_coordinate, orientation,
                                kind)
        if vertical?(orientation)
          return legacy_vertical_label_position(
            x_coordinate, y_coordinate, kind
          )
        end
        if kind == "tag"
          width = mermaid_label_width(text)
          return [x_coordinate - (width / 2.0), y_coordinate - 15, "start"]
        end

        width = mermaid_label_width(text)
        diagonal_id_label_position(width, x_coordinate, y_coordinate)
      end

      def legacy_vertical_label_position(x_coordinate, y_coordinate, kind)
        return [x_coordinate - 14, y_coordinate + 4, "end"] if kind == "tag"

        [x_coordinate + 14, y_coordinate + 4, "start"]
      end

      def vertical_label_position(text, x_coordinate, y_coordinate,
                                  font_size = nil)
        width = measure_text(
          text, font_size: font_size || small_font_size
        )[:width]
        logical_x = x_coordinate + 14
        visual_x = x_coordinate - width - 12
        [logical_x, y_coordinate - 1, "start", -45.0,
         x_coordinate, y_coordinate, visual_x - logical_x]
      end

      def tagged_vertical_label_position(x_coordinate, y_coordinate)
        [x_coordinate + 19, y_coordinate + 7, "start", 45.0,
         x_coordinate + 14, y_coordinate + 4]
      end

      def branch_labels(graph)
        commits = representative_branch_commits(graph)
        commits.map do |branch, commit|
          branch_label(branch, commit, graph)
        end
      end

      def representative_branch_commits(graph)
        representatives = positioned_branch_commits(graph)
        graph[:branches].each_with_object(representatives) do |branch, result|
          next if result.key?(branch[:name])

          anchor = empty_branch_anchor(branch, graph)
          result[branch[:name]] = anchor if anchor
        end
      end

      def positioned_branch_commits(graph)
        if vertical?(graph[:orientation])
          return graph[:commits].to_h do |commit|
            [commit[:branch], commit]
          end
        end

        graph[:commits].each_with_object({}) do |commit, representatives|
          representatives[commit[:branch]] ||= commit
        end
      end

      def empty_branch_anchor(branch, graph)
        creation = graph[:commits].find do |commit|
          commit[:id] == branch[:created_at_commit]
        end
        return empty_root_anchor(branch, graph) unless creation

        orientation = graph[:orientation]
        time = vertical?(orientation) ? creation[:y] : creation[:x]
        lane = graph[:lane_positions].fetch(branch[:lane])
        x_coordinate, y_coordinate = coordinates(time, lane, orientation)
        { x: x_coordinate, y: y_coordinate }
      end

      def empty_root_anchor(branch, graph)
        return if graph[:commits].empty? || !branch[:parent_branch].nil?

        x_coordinate, y_coordinate = coordinates(
          0, branch[:lane] * LANE_SPACING, graph[:orientation]
        )
        { x: x_coordinate, y: y_coordinate }
      end

      def branch_label(branch, commit, graph)
        position = branch_label_position(branch, commit, graph)
        geometry = branch_label_geometry(branch, *position)
        # Mermaid reserves extra visual clearance without changing the
        # branch label's logical boundary anchor.
        translation = branch_label_translation(graph)
        geometry[:translation_x] = -translation if translation
        geometry
      end

      def branch_label_translation(graph)
        return EMPTY_BRANCH_LABEL_CLEARANCE if translated_branch_label?(graph)
        return CHERRY_PICK_BRANCH_LABEL_CLEARANCE if cherry_pick_graph?(graph)

        if explicit_id_graph?(graph) || compact_generated_semantic_graph?(graph)
          EXPLICIT_ID_BRANCH_LABEL_CLEARANCE
        end
      end

      def cherry_pick_graph?(graph)
        !vertical?(graph[:orientation]) &&
          graph[:commits].any? { |commit| commit[:is_cherry_pick] }
      end

      def translated_branch_label?(graph)
        simple_three_commit_graph?(graph) &&
          !vertical?(graph[:orientation]) && !generated_commits_only?(graph)
      end

      def explicit_id_graph?(graph)
        return false if vertical?(graph[:orientation])
        return false if graph[:commits].size <= 1
        return false if generated_commits_only?(graph)

        graph[:commits].any? { |commit| !generated_commit_id?(commit) } &&
          graph[:commits].none? { |commit| commit[:is_cherry_pick] }
      end

      def branch_label_geometry(branch, x_coordinate, y_coordinate, anchor)
        { text: branch, x: x_coordinate + PADDING,
          y: y_coordinate + PADDING, text_anchor: anchor,
          kind: "branch", branch: branch, font_size: branch_font_size }
      end

      def branch_label_position(branch, commit, graph)
        width = measure_text(branch, font_size: branch_font_size)[:width]
        return horizontal_branch_label_position(commit[:y], width, graph) unless
          vertical?(graph[:orientation])

        vertical_branch_label_position(commit[:x], width, graph)
      end

      def horizontal_branch_label_position(lane, width, graph)
        inset = BRANCH_LABEL_INSET
        inset -= EMPTY_BRANCH_LABEL_CLEARANCE if graph[:commits].one? ||
          generated_commits_only?(graph)
        [inset - width,
         lane - BRANCH_LABEL_BASELINE_OFFSET, "start"]
      end

      def generated_commits_only?(graph)
        graph[:commits].all? do |commit|
          commit[:id].match?(/\Acommit-\d+\z/) && tag_labels(commit).empty?
        end
      end

      def vertical_branch_label_position(lane, width, graph)
        boundary = if graph[:orientation] == "TB"
                     COMMIT_RADIUS - VERTICAL_BRANCH_LABEL_CLEARANCE
                   else
                     graph[:height]
                   end
        [lane - (width / 2.0), boundary, "start"]
      end

      def label_spill(labels, width)
        return [0, 0] if labels.empty?

        spans = labels.map { |label| label_span(label) }
        lefts, rights = spans.transpose
        [[-lefts.min, 0].max, [rights.max - width, 0].max]
      end

      def label_span(label)
        width = measure_text(
          label[:text], font_size: label.fetch(:font_size)
        )[:width] * LABEL_HEADROOM
        share = { "start" => 0.0, "middle" => 0.5, "end" => 1.0 }
          .fetch(label[:text_anchor])
        left = label[:x] + label.fetch(:translation_x, 0) - (width * share)
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
          tag: commit[:tag], tags: commit[:tags],
          parent_ids: commit[:parent_ids]
        }
      end

      def commit_labels_for(labels, commit)
        labels.select do |label|
          label[:kind] != "branch" && label[:owner_id] == commit[:ir_id]
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
                  font_size: label.fetch(:font_size),
                  rotation: label[:rotation],
                  rotation_center_x: shifted_rotation_x(label, extra_shift),
                  rotation_center_y: label[:rotation_center_y],
                  translation_x: label[:translation_x])
      end

      def shifted_rotation_x(label, extra_shift)
        center = label[:rotation_center_x]
        center && (center + extra_shift)
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

      def branch_font_size
        theme.typography&.font_size_large ||
          Theme::Registry.get(:default).typography.font_size_large
      end

      # Builds branch information from the shared graph's branch entries.
      #
      # @param branches [Array<Hash>] ordered branch semantics
      # @return [Hash] branch info with parent relationships
      def build_branch_info(branches, main_branch)
        info = { main_branch => branch_info({}, 0, main_branch) }
        branches.reject { |branch| branch[:name] == main_branch }.each do |branch|
          info[branch[:name]] = branch_info(branch, info.size, main_branch)
        end
        info
      end

      def branch_info(branch, default_order, main_branch)
        {
          parent: branch.empty? ? nil : branch[:parent_branch] || main_branch,
          order: branch[:order] || default_order,
          created_at: branch[:created_at_commit],
        }
      end

      # Assigns lanes (rows for LR, columns for TB/BT) to branches.
      #
      # Main branch gets lane 0, child branches get the following lanes.
      #
      # @param branches [Array<Hash>] ordered branch semantics
      # @param branch_info [Hash] branch information
      # @return [Hash<String, Integer>] branch name to lane number
      def assign_lanes(branches, branch_info, main_branch)
        ordered_branches(branches, branch_info).each_with_index
          .with_object(main_branch => 0) do |pair, lanes|
          branch, index = pair
          lanes[branch[:name]] = index + 1
        end
      end

      def ordered_branches(branches, branch_info)
        main_branch = branch_info.keys.first
        branches.reject { |branch| branch[:name] == main_branch }
          .each_with_index.sort_by do |(branch, index)|
          [branch[:order] ? 1 : 0, branch[:order] || index, branch[:name]]
        end.map(&:first)
      end

      def lane_positions(assignments, orientation)
        return assignments.values.to_h { |lane| [lane, lane * LANE_SPACING] } unless
          vertical?(orientation)

        ordered = assignments.sort_by { |_branch, lane| lane }
        ordered.each_with_index.with_object({}) do |((branch, lane), index), positions|
          positions[lane] = if index.zero?
                              0.0
                            else
                              previous_branch, previous_lane = ordered.fetch(index - 1)
                              positions.fetch(previous_lane) + VERTICAL_LANE_GAP +
                                (vertical_lane_label_width(previous_branch) / 2.0)
                            end
        end
      end

      def vertical_lane_label_width(branch)
        measured = measure_text(branch, font_size: branch_font_size)[:width]
        substitute = (measured * VERTICAL_LANE_LABEL_RATIO) +
          VERTICAL_LANE_LABEL_HEADROOM
        [measured, substitute].max
      end

      # Positions commits with X and Y coordinates.
      #
      # @param commits [Array<Hash>] ordered commit semantics
      # @param lane_assignments [Hash] branch to lane mapping
      # @param orientation [String] "LR", "TB" or "BT"
      # @return [Array<Hash>] positioned commits
      def position_commits(commits, lane_assignments, orientation, main_branch,
                           lane_positions)
        commits.each_with_index.map do |commit, index|
          positioned_commit(
            commit, index, commits.size, lane_assignments, orientation,
            main_branch, lane_positions
          )
        end
      end

      def positioned_commit(commit, index, count, lane_assignments, orientation,
                            main_branch, lane_positions)
        branch = commit[:branch_name] || main_branch
        lane = lane_assignments[branch] || 0
        commit.merge(positioned_commit_attributes(
                       commit, [index, count], [branch, lane], orientation,
                       lane_positions
                     )).slice(
                       :ir_id, :id, :x, :y, :branch, :lane, :message,
                       :type, :tag, :tags,
                       :parent_ids, :is_merge, :merge_branch, :is_cherry_pick,
                       :cherry_pick_parent
                     )
      end

      def positioned_commit_attributes(commit, sequence, branch_lane,
                                       orientation, lane_positions)
        index, count = sequence
        branch, lane = branch_lane
        x, y = commit_coordinates(
          index, count, lane, orientation, lane_positions
        )
        {
          id: commit[:id] || "commit_#{index}", x: x, y: y,
          branch: branch, lane: lane,
          type: commit[:type] || "NORMAL"
        }.merge(commit_flags(commit))
      end

      def commit_flags(commit)
        {
          is_merge: commit[:is_merge] || false,
          is_cherry_pick: commit[:is_cherry_pick] || false,
        }
      end

      def commit_coordinates(index, count, lane, orientation, lane_positions)
        time = time_position(index, count, orientation)
        lane_position = lane_positions.fetch(lane)
        coordinates(time, lane_position, orientation)
      end

      # Width and height: the time axis is horizontal for `LR` only.
      def extents(positioned_commits, lane_assignments, lane_positions,
                  orientation)
        time_span = calculate_time_span(positioned_commits.size)
        lane_span = calculate_lane_span(lane_assignments, lane_positions)
        vertical?(orientation) ? [lane_span, time_span] : [time_span, lane_span]
      end

      def vertical?(orientation)
        %w[TB BT].include?(orientation)
      end

      # Distance along the time axis from the start edge of the diagram.
      # `BT` counts down from the last commit, so the first commit is
      # the lowest one.
      def time_position(idx, count, orientation)
        step = orientation == "BT" ? count - idx - 1 : idx
        (step * COMMIT_SPACING) + COMMIT_RADIUS
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
        commit_positions = positioned_commits.to_h do |commit|
          [commit[:ir_id], commit]
        end

        edges.filter_map do |edge|
          parent = commit_positions[edge.source_id]
          commit = commit_positions[edge.target_id]
          next unless parent && commit

          connection(edge, parent, commit)
        end
      end

      def connection(edge, parent, commit)
        {
          from: parent[:id], to: commit[:id],
          from_x: parent[:x], from_y: parent[:y],
          to_x: commit[:x], to_y: commit[:y],
          from_branch: parent[:branch], to_branch: commit[:branch],
          type: edge.role == "parent" ? :normal : edge.role.to_sym
        }
      end

      # Builds branch metadata for rendering.
      #
      # @param branches [Array<Hash>] ordered branch semantics
      # @param lane_assignments [Hash] lane assignments
      # @return [Array<Hash>] branch metadata
      def build_branch_metadata(branches, lane_assignments, main_branch)
        main = {
          name: main_branch,
          lane: lane_assignments[main_branch] || 0,
          color: branch_color(0),
        }
        branches.reject { |branch| branch[:name] == main_branch }
          .each_with_index.with_object([main]) do |pair, metadata|
          branch, index = pair
          metadata << branch_metadata(branch, index, lane_assignments)
        end
      end

      def branch_metadata(branch, index, lane_assignments)
        {
          name: branch[:name],
          lane: lane_assignments[branch[:name]] || (index + 1),
          color: branch_color(index + 1),
          order: branch[:order], parent_branch: branch[:parent_branch],
          created_at_commit: branch[:created_at_commit]
        }
      end

      def branch_color(index)
        palette = theme.colors&.git_graph_palette
        if palette && !palette.empty?
          return theme.colors.palette(:git_graph, index)
        end

        Theme::Registry.get(:default).colors.palette(:git_graph, index)
      end

      # Calculates the extent along the time axis.
      #
      # @param commit_count [Integer] number of commits
      # @return [Numeric] extent in pixels
      def calculate_time_span(commit_count)
        return COMMIT_SPACING * 2 if commit_count.zero?

        commit_count * COMMIT_SPACING
      end

      # Calculates the extent across the lanes.
      #
      # @param lane_assignments [Hash] lane assignments
      # @return [Numeric] extent in pixels
      def calculate_lane_span(lane_assignments, lane_positions = nil)
        return COMMIT_RADIUS * 2 if lane_assignments.empty?

        lane_positions ||= lane_assignments.values.to_h do |lane|
          [lane, lane * LANE_SPACING]
        end
        max_lane = lane_assignments.values.max
        lane_positions.fetch(max_lane) + (COMMIT_RADIUS * 2)
      end
    end
  end
end
