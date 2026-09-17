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
          r.fill = box_property(styles, 'fill', attributed) || '#f9f9f9'
          r.stroke = box_property(styles, 'stroke', attributed) || '#333333'
          r.stroke_width = box_property(styles, 'stroke-width', attributed) || '2'
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
      #   textStyles: ["bgFill:currentcolor", "FILL:currentcolor", "stroke:currentcolor"]
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
        chunks = declaration.split(',')
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
        return false unless chunk.include?('color')

        key, value = mermaid_split(chunk)
        !value.nil? && key.strip != 'fill'
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
        parts = chunk.split(':', -1)
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
        return value unless value&.downcase == 'currentcolor'

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
        values = styles.select { |key, _| key != 'color' && key.downcase == 'color' }.values
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
        when 'fill', 'stroke' then css_color?(value)
        when 'stroke-width' then css_length?(value)
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
          COLOR_PROPERTIES.include?(property) ? resolve_current_color(value, styles) : value
        end
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
