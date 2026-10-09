# frozen_string_literal: true

require "nokogiri"

module SpecSupport
  module LayoutParity
    # Parses ONE svg (an mmdc reference or a Sirena render, same code path)
    # into a Figure whose numbers are in root viewBox user units.
    #
    # The extractor owns geometry (transform composition, nested svg
    # viewports, bboxes, text anchors, containment-derived parents). A
    # recognizer, one per diagram type and shared by both sides, owns which
    # groups are logical elements and what their keys are (contract section 1).
    class SvgFigureExtractor
      SKIPPED = %w[defs marker symbol clipPath mask pattern style script title desc metadata foreignObject].freeze
      SPACE = /\s+/

      def initialize(recognizer)
        @recognizer = recognizer
      end

      def extract(svg)
        @doc = Nokogiri::XML(svg)
        @doc.remove_namespaces!
        root = @doc.root
        raise ArgumentError, "not an svg document" unless root&.name == "svg"

        @ctm = {}
        root_box = self.class.root_box(root)
        walk(root, Matrix.new, [root_box&.width, root_box&.height])
        figure(root, root_box)
      end

      def self.root_box(root)
        vb = root["viewBox"].to_s.scan(Matrix::NUMBER).map(&:to_f)
        return Bbox.new(vb[0], vb[1], vb[0] + vb[2], vb[1] + vb[3]) if vb.size == 4

        w = numeric_length(root["width"])
        h = numeric_length(root["height"])
        w && h ? Bbox.new(0, 0, w, h) : nil
      end

      def self.numeric_length(text)
        return nil if text.nil? || text.include?("%")

        text[Matrix::NUMBER]&.to_f
      end

      # --- services for recognizers --------------------------------------

      attr_reader :doc

      # Union bbox of the shape primitives under `node`, in root units, skipping
      # subtrees whose class is in `exclude`. A node with no shape primitive
      # falls back to the anchor points of its text (contract section 2).
      def bbox(node, exclude: [])
        shapes = collect(node, exclude).select { |n| ShapePoints.primitive?(n) }
        boxes = shapes.map { |n| Bbox.from_points(world(n, ShapePoints.new(n).points)) }
        return Bbox.union(boxes) if boxes.any?

        Bbox.union(collect(node, exclude).select { |n| n.name == "text" }.map { |t| anchor_box(t) })
      end

      # Visible label: text and foreignObject content, tags stripped, <br> as a
      # space, whitespace collapsed.
      def label(node)
        parts = node.xpath(".//text | .//foreignObject").map { |n| flatten(n) }
        parts.join(" ").gsub(SPACE, " ").strip
      end

      private

      def figure(root, root_box)
        found = @recognizer.elements(self, @doc)
        containers = found.select { |e| @recognizer.container_kinds.include?(e.kind) }
        elements = found.map { |e| e.with_parent(parent_key(e, containers)) }
        max_width = root["style"].to_s[/max-width:\s*(#{Matrix::NUMBER})/, 1]&.to_f
        Figure.new(elements: elements, root_box: root_box, max_width: max_width)
      end

      # Parent = the smallest other container that strictly encloses the
      # element. The DOM is not used: mermaid lists clusters flat.
      def parent_key(element, containers)
        enclosing = containers.reject { |c| c.equal?(element) }.select do |c|
          c.bbox.contain?(element.bbox) && c.bbox.area > element.bbox.area
        end
        enclosing.min_by { |c| c.bbox.area }&.key
      end

      def walk(node, parent_ctm, viewport)
        ctm = parent_ctm * Matrix.parse(node["transform"])
        if node.name == "svg" && !node.equal?(@doc.root)
          mapping, viewport = nested_mapping(node, viewport)
          ctm *= mapping
        end
        @ctm[node.pointer_id] = ctm
        node.element_children.each { |child| walk(child, ctm, viewport) unless SKIPPED.include?(child.name) }
      end

      # x/y/width/height plus viewBox/preserveAspectRatio of a nested svg.
      def nested_mapping(node, viewport)
        x = len(node["x"], viewport[0]) || 0.0
        y = len(node["y"], viewport[1]) || 0.0
        w = len(node["width"], viewport[0]) || viewport[0]
        h = len(node["height"], viewport[1]) || viewport[1]
        vb = node["viewBox"].to_s.scan(Matrix::NUMBER).map(&:to_f)
        return [Matrix.translate(x, y), [w, h]] unless vb.size == 4 && w && h

        [view_box_matrix(node, x, y, w, h, vb), [vb[2], vb[3]]]
      end

      def len(text, reference)
        return nil if text.nil?

        value = text[Matrix::NUMBER]&.to_f
        text.include?("%") && reference ? reference * value / 100 : value
      end

      # SVG 1.1 section 7.8: viewBox onto the viewport, default xMidYMid meet.
      def view_box_matrix(node, x, y, w, h, view_box)
        vx, vy, vw, vh = view_box
        align, mode = node["preserveAspectRatio"].to_s.split.then { |p| [p[0] || "xMidYMid", p[1] || "meet"] }
        return Matrix.new(w / vw, 0, 0, h / vh, x - (vx * w / vw), y - (vy * h / vh)) if align == "none"

        sx = w / vw
        sy = h / vh
        s = mode == "slice" ? [sx, sy].max : [sx, sy].min
        Matrix.new(s, 0, 0, s, x + shift(align[1, 3], w - (vw * s)) - (vx * s), y + shift(align[5, 3], h - (vh * s)) - (vy * s))
      end

      def shift(alignment, space)
        { "Min" => 0.0, "Mid" => space / 2, "Max" => space }.fetch(alignment)
      end

      # Descendants-or-self, not entering skipped tags or excluded classes.
      def collect(node, exclude)
        return [] if SKIPPED.include?(node.name) || (node["class"].to_s.split & exclude).any?

        [node] + node.element_children.flat_map { |c| collect(c, exclude) }
      end

      def world(node, points)
        m = @ctm.fetch(node.pointer_id)
        points.map { |x, y| m.apply(x, y) }
      end

      # x/y on the text, else on its first positioned tspan, plus dx/dy of the
      # text and that tspan. Non-numeric units (em) count as 0: no font metrics.
      def anchor_box(text)
        tspan = text.element_children.find { |c| c.name == "tspan" && (c.attribute_nodes.map(&:name) & %w[x y dx dy]).any? }
        pick = ->(name) { text[name] || tspan&.[](name) }
        x = first_number(pick.call("x")) + first_number(text["dx"]) + first_number(tspan&.[]("dx"))
        y = first_number(pick.call("y")) + first_number(text["dy"]) + first_number(tspan&.[]("dy"))
        Bbox.from_points(world(text, [[x, y]]))
      end

      def first_number(text)
        text.to_s[/\A\s*(#{Matrix::NUMBER})(?![a-z%])/, 1].to_f
      end

      def flatten(node)
        node.children.map do |c|
          if c.text? then c.text
          elsif c.name == "br" then " "
          else flatten(c)
          end
        end.join
      end
    end
  end
end
