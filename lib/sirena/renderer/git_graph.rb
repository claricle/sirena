# frozen_string_literal: true

require_relative "base"
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
    # Layout::GitGraph into an SVG visualization showing:
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
      # How much of a label's width lies left of its x, per text-anchor.
      ANCHOR_SHARE = { "start" => 0.0, "middle" => 0.5, "end" => 1.0 }.freeze
      private_constant :ANCHOR_SHARE

      # Renders the layout structure to SVG.
      #
      # @param layout [Hash] layout data from Layout::GitGraph
      # @return [Svg::Document] rendered SVG document
      def render(layout)
        @orientation = layout[:orientation]
        svg = create_document_from_layout(layout)
        inherited = svg.children.size
        draw(layout, svg)
        fit_labels(layout, svg, inherited)

        svg
      end

      protected

      # Creates an SVG document with 40px of padding on every side, so an
      # external override of this method (a protected extension point since
      # the 0.1.0 release) keeps working with one argument.
      #
      # @param layout [Hash] layout data
      # @return [Svg::Document] new SVG document
      def create_document_from_layout(layout)
        build_document_from_layout(layout, padding: 40)
      end

      # Renders in order: connections, then commits, then labels.
      def draw(layout, svg)
        render_connections(layout, svg)
        render_commits(layout, svg)
        render_labels(layout, svg)
      end

      # Widens the box for labels that pass the 40px padding. A label past
      # the left edge also shifts the drawing right, which redraws once, so
      # the render_* hooks (an overridden render_labels too) run twice.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] rendered document, widened in place
      # @param inherited [Integer] children present before drawing started;
      #   a redraw keeps them where they are, so they are not measured
      # @return [void]
      def fit_labels(layout, svg, inherited)
        spill_left, spill_right = label_spill(svg, inherited)
        return if spill_left.zero? && spill_right.zero?

        svg.width += spill_left + spill_right
        svg.view_box = widened_view_box(svg) if svg.view_box
        return unless spill_left.positive?

        redraw_shifted(layout, svg, spill_left, inherited)
      end

      # How far the drawn labels pass the left and the right edge.
      #
      # @return [Array<Numeric>] left spill, right spill; both 0 when fitting
      def label_spill(svg, inherited)
        labels = svg.children.drop(inherited).grep(Svg::Text)
        return [0, 0] if labels.empty?

        lefts, rights = labels.map { |text| label_span(text) }.transpose
        [[-lefts.min, 0].max, [rights.max - svg.width, 0].max]
      end

      # Keeps the origin a subclass's document hook chose and replaces the
      # extent.
      def widened_view_box(svg)
        origin = svg.view_box.split.first(2).join(" ")
        "#{origin} #{svg.width} #{svg.height}"
      end

      def redraw_shifted(layout, svg, shift, inherited)
        @offset_x += shift
        svg.children.slice!(inherited..)
        draw(layout, svg)
      end

      # Horizontal extent of a text label, from its anchor and a width
      # hint that errs wide (see WIDE_CHAR_WIDTH_RATIO): the average
      # TextMeasurement uses clips ordinary ASCII labels at their real width.
      #
      # @param text [Svg::Text] label
      # @return [Array<Float>] left and right edge
      def label_span(text)
        width = label_width(text)
        share = ANCHOR_SHARE.fetch(text.text_anchor, 0.0)
        left = text.x.to_f - (width * share)
        [left, left + width]
      end

      def label_width(text)
        shown = Svg::Escaping.strip_forbidden(Array(text.content).join)
        shown.length * text.font_size.to_f * WIDE_CHAR_WIDTH_RATIO
      end
      private :draw, :fit_labels, :label_spill, :widened_view_box,
              :redraw_shifted, :label_span, :label_width

      # Renders all connections between commits.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_connections(layout, svg)
        # Get branch colors for connections
        branch_colors = layout[:branches].to_h do |b|
          [b[:name], b[:color]]
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
          # Different Y - use bezier curve (a straight line when both X match,
          # as for commits in one TB/BT lane)
          control_x1 = from_x + (to_x - from_x) * 0.5
          control_y1 = from_y
          control_x2 = from_x + (to_x - from_x) * 0.5
          control_y2 = to_y

          path_data = "M #{from_x} #{from_y} " \
                      "C #{control_x1} #{control_y1}, " \
                      "#{control_x2} #{control_y2}, " \
                      "#{to_x} #{to_y}"
        else
          # Same Y - straight line
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

      # The time axis runs top-to-bottom or bottom-to-top, so lanes are
      # columns and labels sit beside the commit rather than below it.
      def vertical?
        %w[TB BT].include?(@orientation)
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
        branch_colors = layout[:branches].to_h do |b|
          [b[:name], b[:color]]
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

        # Render commit ID beside the circle (below it for LR) if present
        if commit[:id] && !commit[:id].start_with?("commit_")
          render_commit_id_label(commit[:id], x, y, svg)
        end

        # Render tag opposite the ID (above the circle for LR) if present
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
          t.x, t.y, t.text_anchor =
            vertical? ? [x + 14, y + 4, "start"] : [x, y + 20, "middle"]
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
          t.x, t.y, t.text_anchor =
            vertical? ? [x - 14, y + 4, "end"] : [x, y - 15, "middle"]
          t.fill = theme_color(:accent) || "#7c3aed"
          t.font_size = (theme_typography(:font_size_small) || 10).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_weight = "bold"
          t.content = tag
        end

        svg.add_element(text)
      end

      # Branch names sit past the last commit, in the direction time runs.
      def branch_label_position(x_pos, y_pos)
        case @orientation
        when "TB" then [x_pos, y_pos + 24, "middle"]
        when "BT" then [x_pos, y_pos - 16, "middle"]
        else [x_pos + 15, y_pos + 4, "start"]
        end
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
          x = commit[:x] + @offset_x
          y = commit[:y] + @offset_y

          branch_meta = layout[:branches].find { |b| b[:name] == branch_name }
          color = branch_meta&.dig(:color) || theme_color(:primary) || "#2563eb"

          text = Svg::Text.new.tap do |t|
            t.x, t.y, t.text_anchor = branch_label_position(x, y)
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
