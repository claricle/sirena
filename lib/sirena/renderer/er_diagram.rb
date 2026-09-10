# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Renderer
    # ER diagram renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles ER entity boxes with
    # attributes, PK/FK markers, and relationship lines with crow's foot
    # cardinality notation.
    #
    # @example Render an ER diagram
    #   renderer = ErDiagramRenderer.new
    #   svg = renderer.render(laid_out_graph)
    class ErDiagramRenderer < Base
      # Font size for entity names
      ENTITY_NAME_FONT_SIZE = 16

      # Font size for attributes
      ATTRIBUTE_FONT_SIZE = 12

      # Line height for text
      LINE_HEIGHT = 18

      # Padding within entity boxes
      BOX_PADDING = 10

      # Cardinality symbol size
      CARDINALITY_SIZE = 15

      # Padding around a diagram that has something in it.
      DIAGRAM_PADDING = 20

      # Padding mermaid puts around an ER diagram that holds nothing: 8px on
      # each side of a zero-size content box, so the canvas comes out 16x16.
      # Measured from spec/fixtures_mermaid/er/061_spec_mermaidapi_spec_60.svg,
      # whose source is the bare `erDiagram` keyword. Sirena keeps its own
      # "0 0" viewBox origin, which every non-empty ER reference in that
      # directory uses; only the extent is copied.
      EMPTY_DIAGRAM_PADDING = 8

      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document(graph, padding: padding_for(graph))

        # Render edges first (so they appear under nodes)
        render_relationships(graph, svg) if graph[:edges]

        # Render entity boxes
        render_entities(graph, svg) if graph[:children]

        svg
      end

      protected

      # Padding for this graph. An empty ER diagram gets mermaid's 8px, so
      # the whole canvas is 16x16; anything else gets the normal 20px.
      def padding_for(graph)
        empty_er_graph?(graph) ? EMPTY_DIAGRAM_PADDING : DIAGRAM_PADDING
      end

      # An empty ER diagram is one that carries BOTH collection keys and holds
      # nothing in either. Key presence is tested separately from the values
      # because a default-valued Hash (`Hash.new([])`) holds no key at all yet
      # answers `[]` to a lookup, so a value test by itself would call it
      # empty and shrink it. Values are compared with `== []` rather than
      # asked `empty?`, so a non-collection value is false here rather than
      # raising.
      #
      # Every other shape is sized by calculate_width/calculate_height from
      # what the lookups return rather than from key presence.
      def empty_er_graph?(graph)
        graph.key?(:children) && graph.key?(:edges) &&
          graph[:children] == [] && graph[:edges] == []
      end

      def calculate_width(graph)
        return 0 if empty_er_graph?(graph)
        return 800 unless graph[:children]

        max_x = graph[:children].map do |node|
          (node[:x] || 0) + (node[:width] || 150)
        end.max || 800

        max_x + 40
      end

      def calculate_height(graph)
        return 0 if empty_er_graph?(graph)
        return 600 unless graph[:children]

        max_y = graph[:children].map do |node|
          (node[:y] || 0) + (node[:height] || 100)
        end.max || 600

        max_y + 40
      end

      def render_entities(graph, svg)
        class_defs = graph[:class_defs] || {}
        graph[:children].each do |node|
          render_entity(node, svg, class_defs)
        end
      end

      def render_entity(node, svg, class_defs)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 150
        height = node[:height] || 100

        metadata = node[:metadata] || {}
        styles = entity_styles(node, class_defs)
        attributed = !metadata[:attributes].to_a.empty?

        # Create group for the entity
        group = Svg::Group.new.tap do |g|
          g.id = "entity-#{node[:id]}"
        end

        # Render outer box
        box = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = width
          r.height = height
          r.fill = box_fill(styles, attributed) || '#f9f9f9'
          r.stroke = box_style(styles, 'stroke') || '#333333'
          r.stroke_width = box_style(styles, 'stroke-width') || '2'
        end
        group.children << box

        # Render entity content
        render_entity_content(node, metadata, group, styles)

        svg << group
      end

      def render_entity_content(node, metadata, group, styles)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 150

        current_y = y + BOX_PADDING + ENTITY_NAME_FONT_SIZE
        # Exact-case lookup, not `box_style` — verified against mermaid's
        # own bundle (isLabelStyle in handDrawnShapeStyles.ts): only a
        # literal lowercase "color" key is routed to the label; any other
        # case (`COLOR`, `Color`) is a box style instead, matched
        # case-insensitively there. Folding this lookup would route an
        # uppercase COLOR onto the entity name.
        name_color = styles['color'] || '#000000'

        # Render entity name
        name = metadata[:name] || node[:id]
        text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = current_y
          t.content = name
          t.fill = name_color
          t.font_family = 'Arial, sans-serif'
          t.font_size = ENTITY_NAME_FONT_SIZE.to_s
          t.text_anchor = 'middle'
          t.font_weight = 'bold'
        end
        group.children << text

        # Add separator after name
        current_y += LINE_HEIGHT
        separator = Svg::Line.new.tap do |l|
          l.x1 = x
          l.y1 = current_y
          l.x2 = x + width
          l.y2 = current_y
          l.stroke = '#333333'
          l.stroke_width = '1'
        end
        group.children << separator

        # Render attributes
        attributes = metadata[:attributes] || []
        current_y += BOX_PADDING
        attributes.each do |attr|
          current_y = render_attribute(x, current_y, styles, attr, group)
        end
      end

      def render_attribute(x, y, styles, attribute, group)
        # Build attribute text with key type marker
        parts = []
        parts << attribute[:key_type] if attribute[:key_type] &&
                                         !attribute[:key_type].empty?
        parts << attribute[:name]
        parts << attribute[:attribute_type] if attribute[:attribute_type] &&
                                               !attribute[:attribute_type]
                                               .empty?

        attr_text = parts.join(' ')

        text = Svg::Text.new.tap do |t|
          t.x = x + BOX_PADDING
          t.y = y + ATTRIBUTE_FONT_SIZE
          t.content = attr_text
          # Exact-case lookup — see the comment on the same lookup in
          # render_entity_content.
          t.fill = styles['color'] || '#000000'
          t.font_family = 'monospace'
          t.font_size = ATTRIBUTE_FONT_SIZE.to_s
        end
        group.children << text

        y + LINE_HEIGHT
      end

      # Every entity carries an implicit `default` class ahead of whatever
      # it was explicitly assigned — verified against mermaid's own db,
      # whose `cssClasses` opens with the literal string "default" for
      # every entity, assigned or not (`"default"`, `"default a"`,
      # `"default a b a"`). A `classDef default` is stored like any other
      # name (grammar and process_class_def need no change for this); this
      # is the one place it has to be applied even when nothing assigned it.
      DEFAULT_CLASS = 'default'
      private_constant :DEFAULT_CLASS

      # Resolves the style properties an entity's classes apply, by name and
      # not by position — an index-keyed lookup would silently swap two
      # entities' colours the moment their class lists diverge in length.
      # Classes merge left to right: a later class overrides an earlier one
      # only on a property both declare, and each contributes any property
      # the other did not. NOT deduped upstream, so a repeated assignment
      # moves that class to the end and lets it win a later conflict —
      # verified against mermaid: `CAR:::a,b` then `CAR:::a` resolves
      # `fill:red` (the trailing "a"), not `fill:blue`.
      #
      # @param node [Hash] the graph node, holding metadata[:classes]
      # @param class_defs [Hash{String => String}] declared classDef styles
      # @return [Hash{String => String}] resolved property => value
      # Classes merge left to right into ONE Hash, not per-class then
      # `Hash#merge!` — mermaid resolves every class's declarations into a
      # single Map at the very end (`styles2Map` in its own bundle), so a
      # chunk from an earlier class and a same-exact-case chunk from a later
      # class must update the SAME Map slot in the SAME left-to-right pass.
      # Plain assignment into one accumulator reproduces that: a repeated
      # exact key updates its value in place (keeping its first position,
      # same as `Map#set` on an existing key) and a new key is appended.
      def entity_styles(node, class_defs)
        assigned = (node[:metadata] || {})[:classes] || []
        classes = [DEFAULT_CLASS, *assigned]

        classes.each_with_object({}) do |class_name, styles|
          declaration = class_defs[class_name]
          next unless declaration

          apply_chunks(class_chunks(declaration), styles)
        end
      end

      # Splits a `classDef` style run ("fill:#f96,stroke:#333") into its raw
      # comma-separated chunks, then REPLAYS a copy of every chunk whose
      # text contains the lowercase substring "color" — anywhere, key or
      # value — onto the end of the list.
      #
      # Verified against mermaid's own db (`ErDB#addClass`): each style
      # chunk is tested with `/color/.exec(s)` (no `i` flag, so only a
      # literal lowercase "color" substring matches) and, on a match, pushed
      # a SECOND time into a separate `textStyles` array that gets appended
      # after this class's own `styles` array when compiling. A declaration
      # naming `stroke:currentcolor` this way ends up LAST among same-key
      # entries even when a later, unrelated `stroke:red` chunk follows it
      # in source — `classDef a stroke:currentcolor,stroke:red` resolves to
      # `currentcolor`, not `red`, because the replay lands after both.
      #
      # @param declaration [String] raw style text for one class
      # @return [Array<String>] chunks, with colour-bearing ones repeated
      def class_chunks(declaration)
        chunks = declaration.split(',')
        chunks + chunks.select { |chunk| chunk.include?('color') }
      end

      # Applies a run of raw chunks into the shared, exact-case styles Hash,
      # left to right. A chunk with no colon is skipped rather than raising
      # — `classDef x foo` and `classDef x font-family:Arial,sans-serif`
      # both parse under mermaid, and the second is exactly this shape after
      # the comma split, so failing here would crash a render on
      # mermaid-valid input.
      #
      # Neither side is folded. Verified against mermaid's own db: it stores
      # a style declaration VERBATIM, case untouched ("FILL:red" stays
      # "FILL:red"). Case-insensitive matching is the BROWSER's doing, on
      # the finished CSS text, not mermaid's — so folding here, before that
      # point, changes results mermaid never produces:
      #
      # - `fill:red,FILL:blue,fill:green` must compute blue in Chrome, not
      #   green. Downcasing collapses all three into one Ruby key up front,
      #   which loses the exact-case Hash entries mermaid's own Map keeps
      #   ("fill" and "FILL" are different keys to it too) and makes the
      #   LAST literal chunk win regardless of case — wrong order. Plain
      #   assignment into one accumulator, above, already reproduces the
      #   ordering a case-preserving Map gives mermaid; box_style below is
      #   what does the browser's case-insensitive resolution, once, at
      #   lookup.
      # - `COLOR:red` (uppercase) must be a BOX style, not a label one —
      #   mermaid's own isLabelStyle check (`key === "color"`,
      #   handDrawnShapeStyles.ts) is exact-case, so `COLOR` fails it.
      #   Downcasing here would fold it into the same key as a real
      #   lowercase `color:`, and a caller reading text color
      #   (`styles['color']`) would pick it up and colour the wrong
      #   element.
      #
      # @param chunks [Array<String>] raw "key:value" chunks, in order
      # @param styles [Hash{String => String}] accumulator, mutated in place
      # @return [Hash{String => String}] the same accumulator, for chaining
      def apply_chunks(chunks, styles)
        chunks.each do |chunk|
          key, value = mermaid_split(chunk)
          next unless value

          styles[key.strip] = value.strip
        end
      end

      # Splits one "key:value" chunk the way mermaid's own `styles2Map`
      # does: `style.split(":")` with NO limit, destructured to only the
      # first two elements. A third colon-separated segment is silently
      # DROPPED, not folded into the value — `fill:red:blue` resolves to
      # `red`, and Chrome computes red from mermaid's own output for that
      # source. `String#split(':', 2)` (the previous behaviour here) instead
      # keeps everything after the first colon, giving `red:blue`, which
      # mermaid never produces.
      #
      # @param chunk [String] one raw "key:value(:ignored)" chunk
      # @return [Array(String, String), Array(String, nil), Array()]
      #   [key, value] — value is nil when the chunk has no colon, and both
      #   are nil (empty array) for an empty chunk
      def mermaid_split(chunk)
        parts = chunk.split(':')
        [parts[0], parts[1]]
      end

      # Case-insensitive box lookup — the counterpart to the exact-case
      # `styles['color']` reads used for text. Resolves the property the
      # BROWSER would end up with: among every entry whose key matches
      # PROPERTY case-insensitively, the one latest in `styles`' (insertion)
      # order wins, same as the last matching CSS declaration in a rendered
      # `style` attribute. Do not use this for `color` — see
      # `apply_chunks`'s second bullet.
      #
      # @param styles [Hash{String => String}] resolved, exact-case entity
      #   styles
      # @param property [String] lowercase property name to resolve
      # @return [String, nil] the winning value, or nil if PROPERTY was
      #   never declared under any case
      def box_style(styles, property)
        styles.select { |key, _| key.downcase == property }.values.last
      end

      # An attributed entity's outer box does NOT go through the browser's
      # CSS cascade the way a bare entity's does — mermaid draws it via a
      # different, row-based shape whose fill comes from a direct, EXACT-key
      # Map read (`stylesMap.get("fill")`, mermaid's own `userNodeOverrides`)
      # rather than an inline `style="..."` attribute the browser resolves
      # case-insensitively. Verified by Codex against the installed mermaid
      # 11.16.1 bundle and a real Chrome computation:
      # `classDef a fill:red,FILL:blue,fill:green` on a bare CAR computes
      # blue (what `box_style` gives), but on `CAR:::a { string make }` it
      # computes green — the last literal lowercase `fill`, ignoring `FILL`
      # entirely. Only `fill` is verified to differ this way; stroke and
      # stroke-width keep resolving through `box_style` either way.
      #
      # @param styles [Hash{String => String}] resolved, exact-case entity
      #   styles
      # @param attributed [Boolean] whether this entity has any attributes
      # @return [String, nil] the winning fill, or nil if never declared
      #   under the case this path reads
      def box_fill(styles, attributed)
        attributed ? styles['fill'] : box_style(styles, 'fill')
      end

      def render_relationships(graph, svg)
        graph[:edges].each do |edge|
          render_relationship(edge, graph, svg)
        end
      end

      def render_relationship(edge, graph, svg)
        source = find_node(graph, edge[:sources]&.first)
        target = find_node(graph, edge[:targets]&.first)

        return unless source && target

        metadata = edge[:metadata] || {}

        # Create group for the relationship
        group = Svg::Group.new.tap do |g|
          g.id = "rel-#{edge[:id]}"
        end

        # Calculate connection points
        source_point = calculate_connection_point(source, target)
        target_point = calculate_connection_point(target, source)

        # Render the line
        rel_type = metadata[:relationship_type] || 'non-identifying'
        render_relationship_line(
          source_point,
          target_point,
          rel_type,
          group
        )

        # Render cardinality markers
        card_from = metadata[:cardinality_from]
        card_to = metadata[:cardinality_to]

        if card_from
          render_cardinality(
            source_point,
            target_point,
            card_from,
            :source,
            group
          )
        end
        if card_to
          render_cardinality(
            target_point,
            source_point,
            card_to,
            :target,
            group
          )
        end

        # Render label if present
        render_relationship_label(edge, source_point, target_point, group)

        svg << group
      end

      def find_node(graph, node_id)
        return nil unless graph[:children] && node_id

        graph[:children].find { |n| n[:id] == node_id }
      end

      def calculate_connection_point(from_node, to_node)
        from_cx = (from_node[:x] || 0) + (from_node[:width] || 150) / 2
        from_cy = (from_node[:y] || 0) + (from_node[:height] || 100) / 2
        to_cx = (to_node[:x] || 0) + (to_node[:width] || 150) / 2
        to_cy = (to_node[:y] || 0) + (to_node[:height] || 100) / 2

        # Determine which edge of the box to connect to
        from_x = from_node[:x] || 0
        from_y = from_node[:y] || 0
        from_w = from_node[:width] || 150
        from_h = from_node[:height] || 100

        # Calculate intersection with box edge
        dx = to_cx - from_cx
        dy = to_cy - from_cy

        # Handle edge cases
        return { x: from_cx, y: from_cy } if dx.abs < 0.001 && dy.abs < 0.001

        # Find intersection point
        if dx.abs > dy.abs
          # Connect left/right edge
          x = dx.positive? ? from_x + from_w : from_x
          y = dy.abs < 0.001 ? from_cy : from_cy + (dy / dx) * (x - from_cx)
        else
          # Connect top/bottom edge
          y = dy.positive? ? from_y + from_h : from_y
          x = dx.abs < 0.001 ? from_cx : from_cx + (dx / dy) * (y - from_cy)
        end

        { x: x, y: y }
      end

      def render_relationship_line(from, to, rel_type, group)
        line = Svg::Line.new.tap do |l|
          l.x1 = from[:x]
          l.y1 = from[:y]
          l.x2 = to[:x]
          l.y2 = to[:y]
          l.stroke = '#333333'
          l.stroke_width = '2'
          l.stroke_dasharray = '5,5' if rel_type == 'non-identifying'
        end
        group.children << line
      end

      def render_cardinality(point, opposite_point, cardinality, _side, group)
        case cardinality
        when 'one'
          render_one_marker(point, opposite_point, group)
        when 'zero_or_more'
          render_zero_or_more_marker(point, opposite_point, group)
        when 'one_or_more'
          render_one_or_more_marker(point, opposite_point, group)
        when 'zero_or_one'
          render_zero_or_one_marker(point, opposite_point, group)
        end
      end

      def render_one_marker(point, opposite_point, group)
        # Single perpendicular line (|)
        dx = opposite_point[:x] - point[:x]
        dy = opposite_point[:y] - point[:y]
        angle = Math.atan2(dy, dx)

        # Perpendicular angle
        perp_angle = angle + Math::PI / 2

        # Calculate perpendicular line endpoints
        half_size = CARDINALITY_SIZE / 2
        x1 = point[:x] + half_size * Math.cos(perp_angle)
        y1 = point[:y] + half_size * Math.sin(perp_angle)
        x2 = point[:x] - half_size * Math.cos(perp_angle)
        y2 = point[:y] - half_size * Math.sin(perp_angle)

        line = Svg::Line.new.tap do |l|
          l.x1 = x1
          l.y1 = y1
          l.x2 = x2
          l.y2 = y2
          l.stroke = '#333333'
          l.stroke_width = '2'
        end
        group.children << line
      end

      def render_zero_or_more_marker(point, opposite_point, group)
        # Circle + crow's foot (o<)
        render_circle_marker(point, opposite_point, group)
        render_crows_foot(point, opposite_point, group)
      end

      def render_one_or_more_marker(point, opposite_point, group)
        # Line + crow's foot (|<)
        render_one_marker(point, opposite_point, group)
        render_crows_foot(point, opposite_point, group)
      end

      def render_zero_or_one_marker(point, opposite_point, group)
        # Circle + line (o|)
        render_circle_marker(point, opposite_point, group)
        render_one_marker(point, opposite_point, group)
      end

      def render_circle_marker(point, opposite_point, group)
        dx = opposite_point[:x] - point[:x]
        dy = opposite_point[:y] - point[:y]
        angle = Math.atan2(dy, dx)

        # Offset the circle along the line
        offset = CARDINALITY_SIZE / 2
        cx = point[:x] + offset * Math.cos(angle)
        cy = point[:y] + offset * Math.sin(angle)

        circle = Svg::Circle.new.tap do |c|
          c.cx = cx
          c.cy = cy
          c.r = CARDINALITY_SIZE / 3
          c.fill = 'none'
          c.stroke = '#333333'
          c.stroke_width = '2'
        end
        group.children << circle
      end

      def render_crows_foot(point, opposite_point, group)
        # Three lines forming crow's foot (< shape)
        dx = opposite_point[:x] - point[:x]
        dy = opposite_point[:y] - point[:y]
        angle = Math.atan2(dy, dx)

        # Offset the crow's foot along the line
        offset = CARDINALITY_SIZE
        base_x = point[:x] + offset * Math.cos(angle)
        base_y = point[:y] + offset * Math.sin(angle)

        # Create three lines at angles
        angles = [-Math::PI / 4, 0, Math::PI / 4]
        angles.each do |angle_offset|
          line_angle = angle + Math::PI + angle_offset
          end_x = base_x + CARDINALITY_SIZE * Math.cos(line_angle)
          end_y = base_y + CARDINALITY_SIZE * Math.sin(line_angle)

          line = Svg::Line.new.tap do |l|
            l.x1 = base_x
            l.y1 = base_y
            l.x2 = end_x
            l.y2 = end_y
            l.stroke = '#333333'
            l.stroke_width = '2'
          end
          group.children << line
        end
      end

      def render_relationship_label(edge, from, to, group)
        labels = edge[:labels] || []
        main_label = labels.find { |l| !l[:position] }
        return unless main_label

        mid_x = (from[:x] + to[:x]) / 2
        mid_y = (from[:y] + to[:y]) / 2

        text = Svg::Text.new.tap do |t|
          t.x = mid_x
          t.y = mid_y - 5
          t.content = main_label[:text]
          t.fill = '#000000'
          t.font_family = 'Arial, sans-serif'
          t.font_size = '11'
          t.text_anchor = 'middle'
        end
        group.children << text
      end
    end
  end
end
