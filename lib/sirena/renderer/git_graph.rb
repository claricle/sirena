# frozen_string_literal: true

require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/line"
require_relative "../svg/path"
require_relative "../svg/text"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Renders a Git Graph layout to SVG.
    #
    # The renderer converts the positioned layout structure from
    # Transform::GitGraph into an SVG visualization showing:
    # - Commit circles at calculated positions
    # - Branch lines connecting parent-child commits
    # - Merge arrows for merge commits
    # - Cherry-pick indicators
    # - Labels for commit IDs, tags, and branches
    #
    # @example Render a git graph
    #   renderer = Renderer::GitGraph.new(theme: my_theme)
    #   svg = renderer.render(layout)
    class GitGraph < Base
      # Renders the layout structure to SVG.
      #
      # @param layout [Hash] layout data from Transform::GitGraph
      # @return [Svg::Document] rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Render in order: connections, then commits, then labels
        render_connections(layout, svg)
        render_commits(layout, svg)
        render_labels(layout, svg)

        svg
      end

      protected

      # Creates an SVG document with dimensions from layout.
      #
      # @param layout [Hash] layout data
      # @return [Svg::Document] new SVG document
      def create_document_from_layout(layout)
        padding = 40

        Svg::Document.new.tap do |doc|
          doc.width = layout[:width] + (padding * 2)
          doc.height = layout[:height] + (padding * 2)
          doc.view_box = "0 0 #{doc.width} #{doc.height}"

          # Add a group with padding offset
          @offset_x = padding
          @offset_y = padding
        end
      end

      # Renders all connections between commits.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_connections(layout, svg)
        # Get branch colors for connections
        branch_colors = layout[:branches].each_with_object({}) do |b, h|
          h[b[:name]] = b[:color]
        end

        layout[:connections].each do |connection|
          case connection[:type]
          when :merge
            render_merge_connection(connection, branch_colors, svg)
          when :cherry_pick
            render_cherry_pick_connection(connection, branch_colors, svg)
          else
            render_normal_connection(connection, branch_colors, svg)
          end
        end
      end

      # Renders a normal parent-child connection.
      #
      # @param connection [Hash] connection data
      # @param branch_colors [Hash] branch name to color mapping
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_normal_connection(connection, branch_colors, svg)
        color = branch_colors[connection[:from_branch]] ||
                branch_colors[connection[:to_branch]] ||
                theme_color(:edge_stroke) || "#666666"

        from_x = connection[:from_x] + @offset_x
        from_y = connection[:from_y] + @offset_y
        to_x = connection[:to_x] + @offset_x
        to_y = connection[:to_y] + @offset_y

        # Draw line from parent to child
        line = Svg::Line.new.tap do |l|
          l.x1 = from_x
          l.y1 = from_y
          l.x2 = to_x
          l.y2 = to_y
          l.stroke = color
          l.stroke_width = "2"
          l.fill = "none"
        end

        svg.add_element(line)
      end

      # Renders a merge connection with curved path.
      #
      # @param connection [Hash] connection data
      # @param branch_colors [Hash] branch name to color mapping
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_merge_connection(connection, branch_colors, svg)
        color = branch_colors[connection[:from_branch]] ||
                theme_color(:edge_stroke) || "#666666"

        from_x = connection[:from_x] + @offset_x
        from_y = connection[:from_y] + @offset_y
        to_x = connection[:to_x] + @offset_x
        to_y = connection[:to_y] + @offset_y

        # Create curved path for merge
        if from_y != to_y
          # Different lanes - use bezier curve
          control_x1 = from_x + (to_x - from_x) * 0.5
          control_y1 = from_y
          control_x2 = from_x + (to_x - from_x) * 0.5
          control_y2 = to_y

          path_data = "M #{from_x} #{from_y} " \
                      "C #{control_x1} #{control_y1}, " \
                      "#{control_x2} #{control_y2}, " \
                      "#{to_x} #{to_y}"
        else
          # Same lane - straight line
          path_data = "M #{from_x} #{from_y} L #{to_x} #{to_y}"
        end

        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.stroke = color
          p.stroke_width = "2"
          p.fill = "none"
          p.stroke_dasharray = "5,3" # Dashed for merge
        end

        svg.add_element(path)
      end

      # Renders a cherry-pick connection with dotted line.
      #
      # @param connection [Hash] connection data
      # @param branch_colors [Hash] branch name to color mapping
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_cherry_pick_connection(connection, branch_colors, svg)
        color = theme_color(:edge_stroke) || "#999999"

        from_x = connection[:from_x] + @offset_x
        from_y = connection[:from_y] + @offset_y
        to_x = connection[:to_x] + @offset_x
        to_y = connection[:to_y] + @offset_y

        path = Svg::Path.new.tap do |p|
          p.d = "M #{from_x} #{from_y} L #{to_x} #{to_y}"
          p.stroke = color
          p.stroke_width = "2"
          p.fill = "none"
          p.stroke_dasharray = "2,4" # Dotted for cherry-pick
        end

        svg.add_element(path)
      end

      # Renders all commits as circles.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_commits(layout, svg)
        # Get branch colors
        branch_colors = layout[:branches].each_with_object({}) do |b, h|
          h[b[:name]] = b[:color]
        end

        layout[:commits].each do |commit|
          render_commit_circle(commit, branch_colors, svg)
        end
      end

      # Renders a single commit as a circle.
      #
      # @param commit [Hash] commit data
      # @param branch_colors [Hash] branch name to color mapping
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_commit_circle(commit, branch_colors, svg)
        x = commit[:x] + @offset_x
        y = commit[:y] + @offset_y
        radius = 8

        # Get color based on branch and commit type
        fill_color = get_commit_fill_color(commit, branch_colors)
        stroke_color = get_commit_stroke_color(commit, branch_colors)

        circle = Svg::Circle.new.tap do |c|
          c.cx = x
          c.cy = y
          c.r = radius
          c.fill = fill_color
          c.stroke = stroke_color
          c.stroke_width = "2"
        end

        svg.add_element(circle)
      end

      # Gets the fill color for a commit based on type and branch.
      #
      # @param commit [Hash] commit data
      # @param branch_colors [Hash] branch colors
      # @return [String] color value
      def get_commit_fill_color(commit, branch_colors)
        case commit[:type]
        when "HIGHLIGHT"
          theme_color(:highlight) || "#fbbf24"
        when "REVERSE"
          theme_color(:background) || "#ffffff"
        else # NORMAL
          branch_colors[commit[:branch]] || theme_color(:primary) || "#2563eb"
        end
      end

      # Gets the stroke color for a commit.
      #
      # @param commit [Hash] commit data
      # @param branch_colors [Hash] branch colors
      # @return [String] color value
      def get_commit_stroke_color(commit, branch_colors)
        case commit[:type]
        when "REVERSE"
          branch_colors[commit[:branch]] || theme_color(:primary) || "#2563eb"
        else
          branch_colors[commit[:branch]] || theme_color(:primary) || "#2563eb"
        end
      end

      # Renders all labels (commit IDs, tags, branches).
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_labels(layout, svg)
        layout[:commits].each do |commit|
          render_commit_labels(commit, svg)
        end

        # Render branch labels at the end of each branch
        render_branch_labels(layout, svg)
      end

      # Renders labels for a single commit.
      #
      # @param commit [Hash] commit data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_commit_labels(commit, svg)
        x = commit[:x] + @offset_x
        y = commit[:y] + @offset_y

        # Render commit ID below the circle if present
        if commit[:id] && !commit[:id].start_with?("commit_")
          render_commit_id_label(commit[:id], x, y, svg)
        end

        # Render tag above the circle if present
        render_tag_label(commit[:tag], x, y, svg) if commit[:tag]
      end

      # Renders a commit ID label.
      #
      # @param id [String] commit ID
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_commit_id_label(id, x, y, svg)
        text = Svg::Text.new.tap do |t|
          t.x = x
          t.y = y + 20
          t.text_anchor = "middle"
          t.fill = theme_color(:label_text) || "#000000"
          t.font_size = (theme_typography(:font_size_small) || 10).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.content = id
        end

        svg.add_element(text)
      end

      # Renders a tag label.
      #
      # @param tag [String] tag name
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_tag_label(tag, x, y, svg)
        text = Svg::Text.new.tap do |t|
          t.x = x
          t.y = y - 15
          t.text_anchor = "middle"
          t.fill = theme_color(:accent) || "#7c3aed"
          t.font_size = (theme_typography(:font_size_small) || 10).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_weight = "bold"
          t.content = tag
        end

        svg.add_element(text)
      end

      # Renders branch name labels.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_branch_labels(layout, svg)
        # Find the last commit for each branch
        branch_last_commits = {}

        layout[:commits].each do |commit|
          branch = commit[:branch]
          branch_last_commits[branch] = commit
        end

        # Render label for each branch at its last commit
        branch_last_commits.each do |branch_name, commit|
          x = commit[:x] + @offset_x + 15
          y = commit[:y] + @offset_y

          branch_meta = layout[:branches].find { |b| b[:name] == branch_name }
          color = branch_meta&.dig(:color) || theme_color(:primary) || "#2563eb"

          text = Svg::Text.new.tap do |t|
            t.x = x
            t.y = y + 4
            t.text_anchor = "start"
            t.fill = color
            t.font_size = (theme_typography(:font_size_small) || 10).to_s
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.font_weight = "bold"
            t.content = branch_name
          end

          svg.add_element(text)
        end
      end
    end
  end
end