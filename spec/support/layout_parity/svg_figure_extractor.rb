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
      SKIPPED = %w[
        defs marker symbol clipPath mask pattern style script title desc
        metadata foreignObject
      ].freeze
      SPACE = /\s+/
      MAX_WIDTH = /max-width:\s*(#{Matrix::NUMBER})/

      def initialize(recognizer)
        @recognizer = recognizer
      end

      def extract(svg)
        root = parse(svg)
        @ctm = {}
        root_box = self.class.root_box(root)
        walk(root, Matrix.identity, viewport_of(root_box))
        figure(root, root_box)
      end

      def self.root_box(root)
        view_box = root["viewBox"].to_s.scan(Matrix::NUMBER).map(&:to_f)
        return Bbox.from_extent(*view_box) if view_box.size == 4

        width = numeric_length(root["width"])
        height = numeric_length(root["height"])
        Bbox.from_extent(0, 0, width, height) if width && height
      end

      def self.numeric_length(text)
        return nil if text.nil? || text.include?("%")

        text[Matrix::NUMBER]&.to_f
      end

      # --- services for recognizers --------------------------------------

      attr_reader :doc

      # Union bbox of the shape primitives under `node`, in root units,
      # skipping subtrees whose class is in `exclude`. A node with no shape
      # primitive falls back to the anchor points of its text (contract
      # section 2).
      def bbox(node, exclude: [])
        nodes = collect(node, exclude)
        shape_bbox(nodes) || text_bbox(nodes)
      end

      # Visible label: text and foreignObject content, tags stripped, <br> as
      # a space, whitespace collapsed.
      def label(node)
        parts = node.xpath(".//text | .//foreignObject").map { |n| flatten(n) }
        parts.join(" ").gsub(SPACE, " ").strip
      end

      private

      def parse(svg)
        @doc = Nokogiri::XML(svg)
        @doc.remove_namespaces!
        root = @doc.root
        raise ArgumentError, "not an svg document" unless root&.name == "svg"

        root
      end

      def viewport_of(root_box)
        [root_box&.width, root_box&.height]
      end

      def figure(root, root_box)
        elements = with_parents(@recognizer.elements(self, @doc))
        max_width = root["style"].to_s[MAX_WIDTH, 1]&.to_f
        Figure.new(elements: elements, root_box: root_box,
                   max_width: max_width)
      end

      def with_parents(found)
        kinds = @recognizer.container_kinds
        containers = found.select { |e| kinds.include?(e.kind) }
        found.map { |e| e.with_parent(parent_key(e, containers)) }
      end

      # Parent = the smallest other container that strictly encloses the
      # element. The DOM is not used: mermaid lists clusters flat.
      def parent_key(element, containers)
        others = containers.reject { |c| c.equal?(element) }
        enclosing = others.select { |c| c.bbox.enclose?(element.bbox) }
        enclosing.min_by { |c| c.bbox.area }&.key
      end

      def walk(node, parent_ctm, viewport)
        ctm = parent_ctm * Matrix.parse(node["transform"])
        if nested_svg?(node)
          nested = NestedViewport.new(node, viewport)
          ctm *= nested.matrix
          viewport = nested.size
        end
        @ctm[node.pointer_id] = ctm
        walk_children(node, ctm, viewport)
      end

      def walk_children(node, ctm, viewport)
        node.element_children.each do |child|
          walk(child, ctm, viewport) unless SKIPPED.include?(child.name)
        end
      end

      def nested_svg?(node)
        node.name == "svg" && !node.equal?(@doc.root)
      end

      # Descendants-or-self, not entering skipped tags or excluded classes.
      def collect(node, exclude)
        classes = node["class"].to_s.split
        return [] if SKIPPED.include?(node.name) || classes.intersect?(exclude)

        [node] + node.element_children.flat_map { |c| collect(c, exclude) }
      end

      def shape_bbox(nodes)
        shapes = nodes.select { |n| ShapePoints.primitive?(n) }
        boxes = shapes.map { |n| shape_box(n) }
        Bbox.union(boxes) if boxes.any?
      end

      def shape_box(shape)
        Bbox.from_points(world(shape, ShapePoints.new(shape).points))
      end

      def text_bbox(nodes)
        texts = nodes.select { |n| n.name == "text" }
        Bbox.union(texts.map { |text| anchor_box(text) })
      end

      def anchor_box(text)
        Bbox.from_points(world(text, [TextAnchor.new(text).point]))
      end

      def world(node, points)
        matrix = @ctm.fetch(node.pointer_id)
        points.map { |x, y| matrix.apply(x, y) }
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
