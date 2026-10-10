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
        svg = create_document(scene)
        render_connections(scene, svg)
        render_commits(scene, svg)
        render_labels(scene, svg)
        svg
      end

      protected

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
        Svg::Line.new.tap do |line|
          line.x1 = connection.from_x
          line.y1 = connection.from_y
          line.x2 = connection.to_x
          line.y2 = connection.to_y
          line.stroke = colour
          line.stroke_width = "2"
          line.fill = "none"
        end
      end

      def connection_colour(connection, branch_colours)
        if connection.type == :cherry_pick
          return theme_color(:edge_stroke) || "#999999"
        end

        branch_colours[connection.from_branch] ||
          branch_colours[connection.to_branch] ||
          theme_color(:edge_stroke) || "#666666"
      end

      def render_commits(scene, svg)
        branch_colours = scene.branches.to_h do |branch|
          [branch.name, branch.color]
        end
        scene.commits.each do |commit|
          svg << commit_circle(commit, branch_colours)
        end
      end

      def commit_circle(commit, branch_colours)
        Svg::Circle.new.tap do |circle|
          circle.cx = commit.x
          circle.cy = commit.y
          circle.r = 8
          circle.fill = commit_fill(commit, branch_colours)
          circle.stroke = commit_stroke(commit, branch_colours)
          circle.stroke_width = "2"
        end
      end

      def commit_fill(commit, branch_colours)
        case commit.type
        when "HIGHLIGHT" then theme_color(:highlight) || "#fbbf24"
        when "REVERSE" then theme_color(:background) || "#ffffff"
        else branch_colours[commit.branch] || theme_color(:primary) || "#2563eb"
        end
      end

      def commit_stroke(commit, branch_colours)
        branch_colours[commit.branch] || theme_color(:primary) || "#2563eb"
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
                        theme_color(:accent) || "#7c3aed"
                      else
                        theme_color(:label_text) || "#000000"
                      end
          text.font_weight = "bold" if geometry.kind == "tag"
        end
      end

      def branch_label(geometry, colour)
        Svg::Text.new.tap do |text|
          apply_label_geometry(text, geometry)
          text.fill = colour || theme_color(:primary) || "#2563eb"
          text.font_weight = "bold"
        end
      end

      def apply_label_geometry(text, geometry)
        text.x = geometry.x
        text.y = geometry.y
        text.text_anchor = geometry.text_anchor
        text.font_size = geometry.font_size.to_s
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.content = geometry.text
      end
    end
  end
end
