# frozen_string_literal: true

require_relative "base"
require_relative "../layout/git_graph"
require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/line"
require_relative "../svg/path"
require_relative "../svg/text"

module Sirena
  module Renderer
    # Emits SVG from final, typed Git-graph geometry.
    class GitGraph < Base
      # @param scene [Layout::GitGraph::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document_from_layout(scene)
        render_connections(scene, svg)
        render_commits(scene, svg)
        render_labels(scene, svg)
        svg
      end

      protected

      # Keep the 0.1.0 protected extension point without duplicating the
      # document construction owned by Renderer::Base.
      alias create_document_from_layout create_document

      def render_connections(scene, svg)
        branch_colours = scene.branches.to_h do |branch|
          [branch.name, branch.color]
        end
        scene.connections.each do |connection|
          svg << connection_element(connection, branch_colours)
        end
      end

      def connection_element(connection, branch_colours)
        colour = connection_colour(connection, branch_colours)
        if connection.type == :normal
          return normal_connection(connection, colour)
        end

        path_connection(connection, colour)
      end

      def path_connection(connection, colour)
        Svg::Path.new.tap do |path|
          path.d = connection.path
          path.stroke = colour
          path.stroke_width = "2"
          path.fill = "none"
          path.stroke_dasharray = connection.type == :merge ? "5,3" : "2,4"
        end
      end

      def normal_connection(connection, colour)
        Svg::Line.new(
          x1: connection.from_x, y1: connection.from_y,
          x2: connection.to_x, y2: connection.to_y,
          stroke: colour, stroke_width: "2", fill: "none"
        )
      end

      def connection_colour(connection, branch_colours)
        if connection.type == :cherry_pick
          return theme_color(:edge_stroke)
        end

        branch_colours[connection.from_branch] ||
          branch_colours[connection.to_branch] ||
          theme_color(:edge_stroke)
      end

      def render_commits(scene, svg)
        branch_colours = scene.branches.to_h do |branch|
          [branch.name, branch.color]
        end
        commits_in_paint_order(scene).each do |commit|
          svg << commit_circle(commit, branch_colours)
        end
      end

      def commits_in_paint_order(scene)
        return scene.commits unless scene.orientation == "BT"

        scene.commits.sort_by(&:y)
      end

      def commit_circle(commit, branch_colours)
        Svg::Circle.new.tap do |circle|
          circle.cx = commit.x
          circle.cy = commit.y
          circle.r = Layout::GitGraph::COMMIT_RADIUS
          circle.fill = commit_fill(commit, branch_colours)
          circle.stroke = commit_stroke(commit, branch_colours)
          circle.stroke_width = "2"
        end
      end

      def commit_fill(commit, branch_colours)
        case commit.type
        when "HIGHLIGHT" then highlight_fill
        when "REVERSE" then reverse_fill
        else standard_commit_fill(commit, branch_colours)
        end
      end

      def highlight_fill
        theme_color(:highlight)
      end

      def reverse_fill
        theme_color(:background)
      end

      def standard_commit_fill(commit, branch_colours)
        branch_colours[commit.branch] || theme_color(:primary)
      end

      def commit_stroke(commit, branch_colours)
        branch_colours[commit.branch] || theme_color(:primary)
      end

      def render_labels(scene, svg)
        scene.commits.each do |commit|
          commit.labels.each { |geometry| svg << commit_label(geometry) }
        end
        scene.branches.each do |branch|
          svg << branch_label(branch.label, branch.color) if branch.label
        end
      end

      def commit_label(geometry)
        Svg::Text.new.tap do |text|
          apply_label_geometry(text, geometry)
          text.fill = if geometry.kind == "tag"
                        theme_color(:accent)
                      else
                        theme_color(:label_text)
                      end
          text.font_weight = "bold" if geometry.kind == "tag"
        end
      end

      def branch_label(geometry, colour)
        Svg::Text.new.tap do |text|
          apply_label_geometry(text, geometry)
          text.fill = colour || theme_color(:primary)
          text.font_weight = "bold"
        end
      end

      def apply_label_geometry(text, geometry)
        apply_label_transform(text, geometry)
        apply_label_typography(text, geometry)
        text.content = geometry.text
      end

      def apply_label_transform(text, geometry)
        text.x = geometry.x
        text.y = geometry.y
        text.class_name = label_class(geometry)
        text.transform = label_transform(geometry)
      end

      def label_class(geometry)
        return "tag-label" if geometry.kind == "tag"

        "commit-label" if geometry.rotation
      end

      def apply_label_typography(text, geometry)
        text.text_anchor = geometry.text_anchor
        text.font_size = geometry.font_size.to_s
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
      end

      def label_transform(geometry)
        transforms = []
        if geometry.rotation
          values = [geometry.rotation, geometry.rotation_center_x,
                    geometry.rotation_center_y]
          transforms << "rotate(#{values.join(' ')})"
        end
        if geometry.translation_x
          transforms << "translate(#{geometry.translation_x} 0)"
        end
        transforms.join(" ") unless transforms.empty?
      end
    end
  end
end
