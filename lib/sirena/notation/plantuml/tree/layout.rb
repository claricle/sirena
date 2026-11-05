# frozen_string_literal: true

require_relative "../../../layout/mindmap"
require_relative "role"

module Sirena
  module Notation
    module PlantUML
      module Tree
        # One laid-out node of a tree: the box it draws and the text in it.
        class Node < Sirena::Layout::Mindmap::Node
          attribute :boxed, :boolean
          attribute :fill, :string
          attribute :corner_radius, :float
          attribute :stroke, :string
          attribute :stroke_width, :float
          attribute :dasharray, :string
          attribute :font_colour, :string
        end

        # A connector, as the path it draws.
        class Edge < Sirena::Layout::Mindmap::Edge
          attribute :stroke_width, :float
          attribute :stroke, :string
          attribute :dasharray, :string
        end

        # What a tree layout hands its renderer.
        class Scene < Sirena::Layout::Scene
          attribute :view_box, :string
          attribute :children, Node, collection: true, default: -> { [] }
          attribute :edges, Edge, collection: true, default: -> { [] }
        end

        # The part of a PlantUML tree layout that mindmaps and work breakdown
        # structures share: it reads the hierarchy graph into a forest, sizes
        # each box from its text, and returns the finished scene. The
        # Mermaid mindmap layout it extends is a force layout; a subclass
        # supplies the tree one through {#place_tree}.
        #
        # @abstract
        class Layout < Sirena::Layout::Mindmap
          MARGIN = 20.0
          PAD_X = 10.0
          PAD_Y = 10.0
          LINE_RATIO = 1.1777
          BASELINE_RATIO = 0.9667
          FILL = "#F1F1F1"
          private_constant :MARGIN, :PAD_X, :PAD_Y, :LINE_RATIO,
                           :BASELINE_RATIO, :FILL

          # A node of the forest with its text measured.
          Item = Struct.new(:id, :level, :side, :boxless, :fill, :lines,
                            :width, :height, :children)
          # A placed box.
          Box = Struct.new(:item, :x, :y) do
            def right
              x + item.width
            end

            def mid_y
              y + (item.height / 2.0)
            end
          end
          private_constant :Item, :Box

          # @param rules [Rules] what the source's `<style>` blocks set
          # @return [Class] this layout, drawing with those rules
          def self.styled(rules)
            return self unless rules.any?

            Class.new(self) { define_method(:rules) { rules } }
          end

          private

          def rules
            @rules ||= Rules.new
          end

          def scene(graph)
            @boxes = []
            @segments = []
            @depths = []
            @row_end = nil
            top = MARGIN
            forest(graph).each do |root|
              top = place_tree(root, top) + gap_between_trees
            end
            build_scene
          end

          def font_size
            raise NotImplementedError
          end

          def gap_between_trees
            raise NotImplementedError
          end

          # @return [Float] the bottom of the placed tree
          def place_tree(_root, _top)
            raise NotImplementedError
          end

          def line_height
            font_size * LINE_RATIO
          end

          def forest(graph)
            by_parent = graph.nodes.group_by(&:parent_id)
            by_parent.fetch(nil, []).map { |node| item(node, by_parent, 1) }
          end

          def item(node, by_parent, level)
            children = by_parent.fetch(node.id, []).map do |child|
              item(child, by_parent, level + 1)
            end
            sized_item(node, level, children)
          end

          def sized_item(node, level, children)
            role = Role.parse(node.role)
            lines = text_lines(node)
            width, height = measured(lines)
            Item.new(node.id, level, role.side, role.boxless, role.fill, lines,
                     width, height, children)
          end

          def text_lines(node)
            lines = node.label.to_s.split("\n", -1)
            lines.empty? ? [""] : lines
          end

          def measured(lines)
            widest = lines.map do |line|
              measure_text(line, font_size: font_size)[:width]
            end.max
            [widest + (2 * PAD_X), (lines.length * line_height) + (2 * PAD_Y)]
          end

          def box(item, left, top)
            Box.new(item, left, top).tap { |placed| @boxes << placed }
          end

          # @param depth [Integer] the depth of the parent the line leaves
          def segment(from_x, from_y, to_x, to_y, depth)
            curve("M#{from_x.round(3)},#{from_y.round(3)} " \
                  "L#{to_x.round(3)},#{to_y.round(3)}", depth)
          end

          def curve(path, depth)
            @segments << path
            @depths << depth
          end

          def build_scene
            shift = MARGIN - @boxes.map(&:x).min.to_f
            width, height = scene_size(shift)
            Scene.new(width: width, height: height,
                      view_box: "0 0 #{width.round(3)} #{height.round(3)}",
                      children: @boxes.map { |b| node(b, shift) },
                      edges: edges(shift))
          end

          def scene_size(shift)
            [(@boxes.map(&:right).max + shift) + MARGIN,
             @boxes.map { |b| b.y + b.item.height }.max + MARGIN]
          end

          def edges(shift)
            @segments.each_with_index.map do |path, index|
              Edge.new(id: "link#{index}", path: shift_path(path, shift),
                       **connector_look(@depths[index]))
            end
          end

          def connector_look(depth)
            look = rules.arrow(depth)
            { stroke_width: look.fetch(:stroke_width, stroke_width),
              stroke: look[:stroke], dasharray: look[:dasharray] }
          end

          def stroke_width
            1.0
          end

          # Every number pair in a path is an `x,y` point.
          def shift_path(path, shift)
            path.gsub(/(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/) do
              px = Regexp.last_match(1).to_f + shift
              "#{px.round(3)},#{Regexp.last_match(2)}"
            end
          end

          def node(placed, shift)
            item = placed.item
            left = placed.x + shift
            Node.new(id: item.id, level: item.level,
                     labels: [label(item, left, placed.y)],
                     **box_geometry(placed, left), **appearance(item))
          end

          def box_geometry(placed, left)
            item = placed.item
            { x: left, y: placed.y, width: item.width, height: item.height,
              center_x: left + (item.width / 2.0), center_y: placed.mid_y }
          end

          def appearance(item)
            look = rules.node(item.level - 1, boxless: item.boxless)
            { shape: item.boxless ? "boxless" : "default",
              boxed: !item.boxless, fill: item.fill || look[:fill] || FILL,
              corner_radius: corner_of(look) }.merge(
                look.slice(:stroke, :stroke_width, :dasharray, :font_colour),
              )
          end

          def corner_radius
            0.0
          end

          # PlantUML draws a corner of half the RoundCorner it is given.
          def corner_of(look)
            look[:round_corner] ? look[:round_corner] / 2.0 : corner_radius
          end

          def label(item, left_edge, top)
            left = left_edge + PAD_X
            first = top + PAD_Y + (font_size * BASELINE_RATIO)
            Label.new(text: item.lines.join("\n"), x: left, y: first.round(3),
                      font_size: font_size,
                      lines: positioned_lines(item, left, first))
          end

          def positioned_lines(item, left, first)
            item.lines.each_with_index.map do |text, index|
              LabelLine.new(text: text, x: left,
                            y: (first + (index * line_height)).round(3))
            end
          end
        end
      end
    end
  end
end
