# frozen_string_literal: true

require_relative "base"
require_relative "../layout/er_diagram"

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
    #   renderer = ErDiagram.new
    #   svg = renderer.render(laid_out_graph)
    class ErDiagram < Base
      # Renders final ER geometry to SVG. Hash input remains accepted as a
      # compatibility boundary and is converted before rendering.
      #
      # @param scene [Layout::ErDiagram::Scene, Hash]
      # @return [Svg::Document] the rendered SVG document
      def render(scene)
        return render_graph(scene) if scene.is_a?(Hash)

        svg = document(scene)
        render_relationships(scene, svg)
        render_entities(scene, svg)

        svg
      end

      protected

      def render_graph(graph)
        svg = create_document(
          graph, padding: Layout::ErDiagram.diagram_padding(graph)
        )
        render_relationships(graph, svg) if graph[:edges]
        render_entities(graph, svg) if graph[:children]
        svg
      end

      def document(scene)
        Svg::Document.new.tap do |svg|
          svg.width = scene.width
          svg.height = scene.height
          svg.view_box = scene.view_box
        end
      end

      def emit_entities(nodes, class_defs, svg)
        nodes.each { |node| emit_entity(node, class_defs, svg) }
      end

      def emit_entity(node, class_defs, svg)
        styles = entity_styles(node, class_defs)
        group = Svg::Group.new.tap { |item| item.id = "entity-#{node.id}" }
        group.children << entity_box(node, styles)
        emit_entity_content(node, group, styles)
        svg << group
      end

      def entity_box(node, styles)
        attributed = node.attributes.any?
        Svg::Rect.new.tap do |rect|
          rect.x = node.x
          rect.y = node.y
          rect.width = node.width
          rect.height = node.height
          rect.fill = box_property(styles, "fill", attributed) || "#f9f9f9"
          rect.stroke = box_property(styles, "stroke", attributed) || "#333333"
          rect.stroke_width =
            box_property(styles, "stroke-width", attributed) || "2"
        end
      end

      def emit_entity_content(node, group, styles)
        emit_entity_header(node, group, styles)
        node.attributes.each do |attribute|
          emit_attribute(attribute, styles, group)
        end
      end

      def emit_entity_header(node, group, styles)
        name_color = styles["color"] || "#000000"
        label = node.labels.first
        text = Svg::Text.new.tap do |t|
          t.x = label.x
          t.y = label.y
          t.content = label.text
          t.fill = name_color
          t.font_family = "Arial, sans-serif"
          t.font_size = font_size_value(label.font_size)
          t.text_anchor = "middle"
          t.font_weight = "bold"
        end
        group.children << text
        separator = Svg::Line.new.tap do |l|
          l.x1 = node.separator.x1
          l.y1 = node.separator.y1
          l.x2 = node.separator.x2
          l.y2 = node.separator.y2
          l.stroke = "#333333"
          l.stroke_width = "1"
        end
        group.children << separator
      end

      def emit_attribute(attribute, styles, group)
        text = Svg::Text.new(
          x: attribute.x,
          y: attribute.y,
          content: attribute.text,
          fill: styles["color"] || "#000000",
          font_family: "monospace",
          font_size: font_size_value(attribute.font_size),
        )
        group.children << text
      end

      # Every entity carries an implicit `default` class ahead of whatever
      # it was explicitly assigned — verified against mermaid's own db,
      # whose `cssClasses` opens with the literal string "default" for
      # every entity, assigned or not (`"default"`, `"default a"`,
      # `"default a b a"`). A `classDef default` is stored like any other
      # name (grammar and process_class_def need no change for this); this
      # is the one place it has to be applied even when nothing assigned it.
      DEFAULT_CLASS = "default"
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
        classes = [DEFAULT_CLASS, *node.classes]

        classes.each_with_object({}) do |class_name, styles|
          declaration = class_defs.find { |item| item.name == class_name }
          next unless declaration

          apply_chunks(class_chunks(declaration.declaration), styles)
        end
      end

      # Splits a `classDef` style run ("fill:#f96,stroke:#333") into its raw
      # comma-separated chunks, then REPLAYS a copy of every chunk whose
      # text contains the lowercase substring "color" — anywhere, key or
      # value — onto the end of the list, EXCEPT one declaring `fill`.
      #
      # Verified against mermaid's own db (`ErDB#addClass`): each style
      # chunk is tested with `/color/.exec(s)` (no `i` flag, so only a
      # literal lowercase "color" substring matches) and, on a match, pushed
      # a SECOND time into a separate `textStyles` array that gets appended
      # after this class's own `styles` array when compiling. A declaration
      # naming `stroke:currentcolor` this way ends up LAST among same-key
      # entries even when a later, unrelated `stroke:red` chunk follows it
      # in source — `classDef a stroke:currentcolor,stroke:#0000ff`
      # resolves to `currentcolor`, not `#0000ff`, because the replay
      # lands after both.
      #
      # `textStyles` is applied after this class's own styles, so a replayed
      # chunk lands last among same-key entries. mermaid defuses that for
      # `fill` by RENAMING it: the chunk pushed into `textStyles` becomes
      # `bgFill:...`, which no longer collides with the box's `fill`.
      #
      # That rename is CASE-SENSITIVE, which is why the exemption below is
      # too. Executing mermaid's own db API for these declarations returns
      #
      #   textStyles: ["bgFill:currentcolor", "FILL:currentcolor",
      #                "stroke:currentcolor"]
      #
      # — lowercase `fill` rewritten, `FILL` left alone to collide as before.
      # Folding the key here would exempt `FILL` as well and change a
      # behaviour mermaid does not change.
      #
      # Measured with mmdc on an erDiagram entity carrying an attribute
      # block, one class assigned:
      #
      #   stroke:currentcolor,stroke:#0000ff  ->  currentcolor
      #   fill:currentcolor,fill:#0000ff      ->  #0000ff
      #   stroke:#00ff00,stroke:#0000ff       ->  #0000ff
      #   fill:#00ff00,fill:#0000ff           ->  #0000ff
      #
      # Row one is why the replay exists. Row two is why lowercase `fill`
      # is exempt: replaying it reverses that row to `currentcolor`.
      #
      # @param declaration [String] raw style text for one class
      # @return [Array<String>] chunks, with colour-bearing ones repeated
      def class_chunks(declaration)
        chunks = declaration.split(",")
        chunks + chunks.select { |chunk| replayed_chunk?(chunk) }
      end

      # Whether CHUNK is one whose `textStyles` replay is still visible on
      # the entity BOX. See `class_chunks` for the measurement behind the
      # `fill` exemption.
      #
      # The key is compared EXACTLY, not folded. mermaid's rename of `fill`
      # to `bgFill` is case-sensitive, so `FILL:` is still replayed and
      # still collides. Folding here would exempt it too, and change a
      # behaviour this commit has no business changing.
      #
      # @param chunk [String] one raw comma-separated chunk
      # @return [Boolean]
      def replayed_chunk?(chunk)
        return false unless chunk.include?("color")

        key, value = mermaid_split(chunk)
        !value.nil? && key.strip != "fill"
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
      # `-1` is required to match JavaScript's `split`: Ruby's default
      # `split` drops a TRAILING empty field, so `"fill:".split(':')` gives
      # `["fill"]` and a value-clearing declaration reads as "no colon" and
      # is skipped, leaving a stale earlier `fill:red` in place. JavaScript
      # (and this, with `-1`) both give `["fill", ""]` instead — `present`
      # below is what then treats that resolved empty value as "never
      # validly declared" once a caller reads it back, matching a browser
      # dropping an empty CSS declaration and mermaid's own JS-falsy read.
      #
      # @param chunk [String] one raw "key:value(:ignored)" chunk
      # @return [Array(String, String), Array(String, nil), Array()]
      #   [key, value] — value is nil when the chunk has no colon, and both
      #   are nil (empty array) for an empty chunk
      def mermaid_split(chunk)
        parts = chunk.split(":", -1)
        [parts[0], parts[1]]
      end

      # An empty string is a validly-parsed but empty CSS value — mermaid's
      # own override read is JS-falsy on it, and the browser drops an empty
      # declaration (`fill:`) during cascade — so both treat it as though
      # the property was never declared. Applied to the exact-key
      # (attributed) read below; the case-insensitive `box_style` path
      # below reaches the same result through `css_valid?` instead, since
      # an empty string is not valid CSS for any property this file models.
      #
      # @param value [String, nil]
      # @return [String, nil] VALUE, or nil if it is nil or empty
      def present(value)
        value.nil? || value.empty? ? nil : value
      end

      # Picks the entry nearest the end of VALUES whose value passes the
      # block, treating an explicitly-cleared empty value (see `present`)
      # as absent rather than invalid. When nothing validates, falls back
      # to the raw last-declared value instead of nil — a hostile or
      # malformed value must still reach the rendered SVG verbatim
      # (escaped by the XML serializer, not by us silently discarding it
      # for our own default), which is exactly the guarantee the D2
      # integration spec pins. Only used where that guarantee applies —
      # see `ambient_color` below for the one caller that must NOT fall
      # back this way.
      #
      # @param values [Array<String, nil>] raw candidate values, in
      #   source order
      # @yield [String] validity predicate
      # @return [String, nil] the winning value, or nil if VALUES held
      #   nothing but absent (nil or empty) entries
      def last_valid_or_raw(values, &)
        present_values = values.filter_map { |value| present(value) }
        return nil if present_values.empty?

        present_values.reverse_each.find(&) || present_values.last
      end

      # Case-insensitive box lookup for a BARE entity, modeling the
      # browser's cascade on the box's `style=` attribute: among every
      # entry whose key matches PROPERTY case-insensitively, in source
      # order, the value nearest the end wins — same as the last matching
      # CSS declaration in a rendered `style` attribute — but an entry
      # whose value the browser's CSS parser would reject is skipped,
      # exactly as an invalid declaration never reaches the cascade at
      # all. Do not use this for `color` — see `apply_chunks`'s second
      # bullet.
      #
      # @param styles [Hash{String => String}] resolved, exact-case entity
      #   styles
      # @param property [String] lowercase property name to resolve
      # @return [String, nil] the winning value, or nil if PROPERTY was
      #   never declared under any case
      def box_style(styles, property)
        values = styles.select { |key, _| key.downcase == property }.values
        last_valid_or_raw(values) { |value| css_valid?(property, value) }
      end

      # `currentColor` on a bare entity's box resolves, in a real browser,
      # against that SAME element's `color` CSS property — which mermaid
      # routes onto the box's `style=` attribute under any casing EXCEPT a
      # literal lowercase `color` key (that one is a label style, see the
      # exact-case `styles['color']` reads above, and never reaches the
      # box's style attribute at all). Substitute the concrete value now,
      # since a standalone SVG has no browser cascade left to resolve it
      # at paint time.
      #
      # @param value [String, nil] PROPERTY's already-resolved raw value
      # @param styles [Hash{String => String}] resolved, exact-case entity
      #   styles
      # @return [String, nil] VALUE, or the ambient colour declared for
      #   this box if VALUE is `currentColor` (any case) and one exists
      def resolve_current_color(value, styles)
        return value unless value&.downcase == "currentcolor"

        ambient_color(styles) || value
      end

      # The ambient colour a bare entity's box would compute `color` as:
      # every key matching `color` case-insensitively EXCEPT the literal
      # lowercase key, which is the label style excluded from the box's
      # own `style=` attribute — see `resolve_current_color` above. Unlike
      # `box_style`, an invalid ambient declaration is simply absent
      # rather than falling back to its raw text — `resolve_current_color`
      # already has a safe literal default (leave `currentColor` as
      # written, which a standalone browser resolves to black, matching
      # mermaid with no ambient colour set), so there is no verbatim
      # guarantee to uphold here the way there is for the fill/stroke
      # attribute itself.
      #
      # @param styles [Hash{String => String}] resolved, exact-case entity
      #   styles
      # @return [String, nil] the winning ambient colour, or nil if none
      #   was validly declared
      def ambient_color(styles)
        values = styles.select do |key, _value|
          key != "color" && key.downcase == "color"
        end.values
        values.filter_map { |value| present(value) }
          .reverse_each.find { |value| css_color?(value) }
      end

      # Colour-valued box properties resolve `currentColor` against the
      # box's ambient colour (see `resolve_current_color`); length-valued
      # ones do not.
      COLOR_PROPERTIES = %w[fill stroke].freeze
      private_constant :COLOR_PROPERTIES

      # Whether VALUE is syntactically valid CSS for PROPERTY. A small
      # table, not a CSS grammar — enough to tell a real declaration from
      # `FILL:bogus`, not to validate every legal `rgb()` argument. A
      # property this table has no opinion on is always valid, so
      # `box_style` never rejects a property it does not model.
      #
      # @param property [String] lowercase property name
      # @param value [String]
      # @return [Boolean]
      def css_valid?(property, value)
        case property
        when "fill", "stroke" then css_color?(value)
        when "stroke-width" then css_length?(value)
        else true
        end
      end

      CSS_HEX_COLOR = /\A#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})\z/i
      private_constant :CSS_HEX_COLOR

      CSS_COLOR_FUNCTION = /\A(?:rgb|rgba|hsl|hsla)\(.+\)\z/i
      private_constant :CSS_COLOR_FUNCTION

      CSS_LENGTH = %r{\A\d+(?:\.\d+)?(?:px|em|rem|%|pt|cm|mm|in|pc|ex|ch|vw|vh)?\z}i
      private_constant :CSS_LENGTH

      # The CSS Color Module Level 4 extended keyword set, plus `none` (a
      # valid `fill`/`stroke` paint keyword, not a general colour) and the
      # two keywords that resolve dynamically (`currentcolor`) or to
      # nothing (`transparent`). Not exhaustive of every legal CSS
      # <color> (system colours, `color(...)`, `lab()` and friends are
      # not corpus-observed here) — sufficient to separate a real
      # declaration from `bogus`.
      CSS_COLOR_KEYWORDS = %w[
        aliceblue antiquewhite aqua aquamarine azure beige bisque black
        blanchedalmond blue blueviolet brown burlywood cadetblue
        chartreuse chocolate coral cornflowerblue cornsilk crimson cyan
        currentcolor darkblue darkcyan darkgoldenrod darkgray darkgreen
        darkgrey darkkhaki darkmagenta darkolivegreen darkorange
        darkorchid darkred darksalmon darkseagreen darkslateblue
        darkslategray darkslategrey darkturquoise darkviolet deeppink
        deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite
        forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray
        green greenyellow grey honeydew hotpink indianred indigo ivory
        khaki lavender lavenderblush lawngreen lemonchiffon lightblue
        lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen
        lightgrey lightpink lightsalmon lightseagreen lightskyblue
        lightslategray lightslategrey lightsteelblue lightyellow lime
        limegreen linen magenta maroon mediumaquamarine mediumblue
        mediumorchid mediumpurple mediumseagreen mediumslateblue
        mediumspringgreen mediumturquoise mediumvioletred midnightblue
        mintcream mistyrose moccasin navajowhite navy none oldlace olive
        olivedrab orange orangered orchid palegoldenrod palegreen
        paleturquoise palevioletred papayawhip peachpuff peru pink plum
        powderblue purple rebeccapurple red rosybrown royalblue
        saddlebrown salmon sandybrown seagreen seashell sienna silver
        skyblue slateblue slategray slategrey snow springgreen steelblue
        tan teal thistle tomato transparent turquoise violet wheat white
        whitesmoke yellow yellowgreen
      ].freeze
      private_constant :CSS_COLOR_KEYWORDS

      # @param value [String]
      # @return [Boolean] whether VALUE is a CSS colour (or the `none`
      #   paint keyword) mermaid's browser cascade would accept, rather
      #   than dropping the declaration
      def css_color?(value)
        downcased = value.downcase
        CSS_COLOR_KEYWORDS.include?(downcased) ||
          CSS_HEX_COLOR.match?(value) ||
          CSS_COLOR_FUNCTION.match?(value)
      end

      # @param value [String]
      # @return [Boolean] whether VALUE is a CSS <length> `stroke-width`
      #   would accept
      def css_length?(value)
        CSS_LENGTH.match?(value)
      end

      # An attributed entity's outer box does NOT go through the browser's
      # CSS cascade the way a bare entity's does — mermaid draws it via a
      # different, row-based shape whose fill, stroke, AND stroke-width
      # each come from a direct, EXACT-key Map read (`stylesMap.get(...)`,
      # mermaid's own `userNodeOverrides`) rather than an inline
      # `style="..."` attribute the browser resolves case-insensitively.
      # Verified by Codex against the installed mermaid 11.16.1 bundle and
      # a real Chrome computation, for all three properties:
      # `classDef a fill:red,FILL:blue,fill:green` on a bare CAR computes
      # blue (what `box_style` gives), but on `CAR:::a { string make }` it
      # computes green — the last literal lowercase `fill`, ignoring
      # `FILL` entirely. `stroke:red,STROKE:blue,stroke:green,
      # stroke-width:2px,STROKE-WIDTH:8px,stroke-width:4px` computes
      # green/4px attributed, blue/8px bare — the same split, on both
      # properties.
      #
      # `currentColor` is never resolved against an ambient colour on this
      # path — an attributed box carries no `style=` attribute for the
      # browser to cascade a `color` property through, so it has no
      # ambient colour to read under any case, and the exact-key value is
      # used verbatim.
      #
      # @param styles [Hash{String => String}] resolved, exact-case entity
      #   styles
      # @param property [String] lowercase property name to resolve
      # @param attributed [Boolean] whether this entity has any attributes
      # @return [String, nil] the winning value, or nil if never validly
      #   declared under the case this path reads
      def box_property(styles, property, attributed)
        if attributed
          present(styles[property])
        else
          value = box_style(styles, property)
          if COLOR_PROPERTIES.include?(property)
            resolve_current_color(value, styles)
          else
            value
          end
        end
      end

      def emit_relationships(edges, svg)
        edges.each { |edge| emit_relationship(edge, svg) }
      end

      def emit_relationship(edge, svg)
        group = Svg::Group.new.tap { |item| item.id = "rel-#{edge.id}" }
        edge.sections.each do |section|
          group.children << relationship_shape(section, edge.relationship_type)
        end
        emit_marker(edge.source_marker, group)
        emit_marker(edge.target_marker, group)
        if edge.labels.any?
          group.children << relationship_text(edge.labels.first)
        end
        svg << group
      end

      def relationship_shape(section, relationship_type)
        return relationship_line(section, relationship_type) if
          section.bend_points.empty?

        relationship_path(section, relationship_type)
      end

      def relationship_line(section, relationship_type)
        Svg::Line.new.tap do |line|
          line.x1 = section.start_point.x
          line.y1 = section.start_point.y
          line.x2 = section.end_point.x
          line.y2 = section.end_point.y
          relationship_stroke(line, relationship_type)
        end
      end

      def relationship_path(section, relationship_type)
        Svg::Path.new.tap do |path|
          path.d = relationship_path_data(section)
          path.fill = "none"
          relationship_stroke(path, relationship_type)
        end
      end

      def relationship_path_data(section)
        points = [section.start_point, *section.bend_points, section.end_point]
        first = points.shift
        (["M #{point_pair(first)}"] +
          points.map { |point| "L #{point_pair(point)}" }).join(" ")
      end

      def point_pair(point)
        "#{point.x} #{point.y}"
      end

      def relationship_stroke(shape, relationship_type)
        shape.stroke = "#333333"
        shape.stroke_width = "2"
        if relationship_type == "non-identifying"
          shape.stroke_dasharray = "5,5"
        end
      end

      def emit_marker(marker, group)
        if marker.circle_first
          marker.circles.each { |geometry| group.children << marker_circle(geometry) }
        end
        marker.lines.each { |geometry| group.children << marker_line(geometry) }
        return if marker.circle_first

        marker.circles.each { |geometry| group.children << marker_circle(geometry) }
      end

      def marker_line(geometry)
        Svg::Line.new.tap do |line|
          line.x1 = geometry.x1
          line.y1 = geometry.y1
          line.x2 = geometry.x2
          line.y2 = geometry.y2
          line.stroke = "#333333"
          line.stroke_width = "2"
        end
      end

      def marker_circle(geometry)
        Svg::Circle.new.tap do |circle|
          circle.cx = geometry.cx
          circle.cy = geometry.cy
          circle.r = geometry.radius
          circle.fill = "none"
          circle.stroke = "#333333"
          circle.stroke_width = "2"
        end
      end

      def relationship_text(label)
        Svg::Text.new(
          x: label.x,
          y: label.y,
          content: label.text,
          fill: "#000000",
          font_family: "Arial, sans-serif",
          font_size: font_size_value(label.font_size),
          text_anchor: "middle",
        )
      end

      def font_size_value(font_size)
        font_size.to_i == font_size ? font_size.to_i.to_s : font_size.to_s
      end

      # Released protected hooks. Hash compatibility delegates geometry
      # recovery to Layout; typed scenes already carry final geometry.
      def calculate_width(graph)
        Layout::ErDiagram.content_width(graph)
      end

      def calculate_height(graph)
        Layout::ErDiagram.content_height(graph)
      end

      def render_entities(graph, svg)
        if graph.is_a?(Layout::ErDiagram::Scene)
          return emit_entities(graph.children, graph.class_defs, svg)
        end

        render_graph_entities(graph, svg)
      end

      def render_graph_entities(graph, svg)
        previous = @compatibility_class_defs
        @compatibility_class_defs = Layout::ErDiagram.from_graph(
          graph, theme: theme
        ).class_defs
        graph[:children].each { |node| render_entity(node, svg) }
      ensure
        @compatibility_class_defs = previous
      end

      def render_entity(node, svg)
        entity = Layout::ErDiagram.entity_from_hash(node, theme: theme)
        styles = entity_styles(entity, @compatibility_class_defs || [])
        group = Svg::Group.new.tap { |item| item.id = "entity-#{entity.id}" }
        group.children << entity_box(entity, styles)
        with_compatibility_styles(styles) do
          render_entity_content(node, node[:metadata] || {}, group)
        end
        svg << group
      end

      def with_compatibility_styles(styles)
        previous = @compatibility_styles
        @compatibility_styles = styles
        yield
      ensure
        @compatibility_styles = previous
      end

      def render_entity_content(node, metadata, group)
        entity = Layout::ErDiagram.entity_from_hash(
          node.merge(metadata: metadata), theme: theme
        )
        emit_entity_header(entity, group, @compatibility_styles || {})
        current_y = entity.separator.y1 + Layout::ErDiagram::ENTITY_PADDING
        (metadata[:attributes] || []).each do |attribute|
          current_y = render_attribute(
            entity.x, current_y, entity.width, attribute, group
          )
        end
      end

      def render_attribute(x, y, _width, attribute, group)
        row = Layout::ErDiagram.attribute_row(
          x, y, attribute, theme: theme
        )
        emit_attribute(row, @compatibility_styles || {}, group)
        y + Layout::ErDiagram::TEXT_LINE_HEIGHT
      end

      def render_relationships(graph, svg)
        if graph.is_a?(Layout::ErDiagram::Scene)
          return emit_relationships(graph.edges, svg)
        end

        graph[:edges].each do |edge|
          render_relationship(edge, graph, svg)
        end
      end

      def render_relationship(edge, graph, svg)
        source = find_node(graph, edge[:sources]&.first)
        target = find_node(graph, edge[:targets]&.first)
        return unless source && target

        metadata = edge[:metadata] || {}
        from = calculate_connection_point(source, target)
        to = calculate_connection_point(target, source)
        group = Svg::Group.new.tap { |item| item.id = "rel-#{edge[:id]}" }
        render_relationship_line(
          from, to, metadata[:relationship_type] || "non-identifying", group
        )
        if metadata[:cardinality_from]
          render_cardinality(
            from, to, metadata[:cardinality_from], :source, group
          )
        end
        if metadata[:cardinality_to]
          render_cardinality(
            to, from, metadata[:cardinality_to], :target, group
          )
        end
        render_relationship_label(edge, from, to, group)
        svg << group
      end

      def find_node(graph, node_id)
        Layout::ErDiagram.find_node(graph, node_id)
      end

      def calculate_connection_point(from_node, to_node)
        point = Layout::ErDiagram.connection_point(from_node, to_node)
        { x: point.x, y: point.y }
      end

      def render_relationship_line(from, to, rel_type, group)
        section = Layout::ErDiagram.section(from, to)
        group.children << relationship_line(section, rel_type)
      end

      def render_cardinality(point, opposite_point, cardinality, _side, group)
        case cardinality
        when "one"
          render_one_marker(point, opposite_point, group)
        when "zero_or_more"
          render_zero_or_more_marker(point, opposite_point, group)
        when "one_or_more"
          render_one_or_more_marker(point, opposite_point, group)
        when "zero_or_one"
          render_zero_or_one_marker(point, opposite_point, group)
        end
      end

      def render_one_marker(point, opposite_point, group)
        marker = Layout::ErDiagram.one_marker(point, opposite_point)
        emit_marker(marker, group)
      end

      def render_zero_or_more_marker(point, opposite_point, group)
        render_circle_marker(point, opposite_point, group)
        render_crows_foot(point, opposite_point, group)
      end

      def render_one_or_more_marker(point, opposite_point, group)
        render_one_marker(point, opposite_point, group)
        render_crows_foot(point, opposite_point, group)
      end

      def render_zero_or_one_marker(point, opposite_point, group)
        render_circle_marker(point, opposite_point, group)
        render_one_marker(point, opposite_point, group)
      end

      def render_circle_marker(point, opposite_point, group)
        marker = Layout::ErDiagram.circle_marker(point, opposite_point)
        emit_marker(marker, group)
      end

      def render_crows_foot(point, opposite_point, group)
        marker = Layout::ErDiagram.crows_marker(point, opposite_point)
        emit_marker(marker, group)
      end

      def render_relationship_label(edge, from, to, group)
        label = Layout::ErDiagram.edge_label(
          edge, from, to, theme: theme
        )
        group.children << relationship_text(label) if label
      end
    end
  end
end
