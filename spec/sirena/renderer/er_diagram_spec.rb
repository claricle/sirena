# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::ErDiagramRenderer do
  let(:renderer) { described_class.new }

  describe '#render' do
    let(:graph) do
      {
        id: 'er_diagram',
        children: [
          {
            id: 'CUSTOMER',
            x: 10,
            y: 10,
            width: 180,
            height: 120,
            labels: [{ text: 'CUSTOMER', width: 80, height: 16 }],
            metadata: {
              name: 'CUSTOMER',
              attributes: [
                { name: 'id', attribute_type: 'int', key_type: 'PK' },
                { name: 'name', attribute_type: 'string', key_type: nil }
              ]
            }
          },
          {
            id: 'ORDER',
            x: 250,
            y: 10,
            width: 180,
            height: 100,
            labels: [{ text: 'ORDER', width: 60, height: 16 }],
            metadata: {
              name: 'ORDER',
              attributes: [
                { name: 'order_id', attribute_type: 'int', key_type: 'PK' }
              ]
            }
          }
        ],
        edges: [
          {
            id: 'CUSTOMER_to_ORDER',
            sources: ['CUSTOMER'],
            targets: ['ORDER'],
            labels: [{ text: 'places' }],
            metadata: {
              relationship_type: 'non-identifying',
              cardinality_from: 'one',
              cardinality_to: 'zero_or_more'
            }
          }
        ]
      }
    end

    it 'renders graph to SVG document' do
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it 'includes entity boxes in SVG' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end
      expect(groups.length).to eq(2)
    end

    it 'renders entity boxes as rectangles' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
      expect(rects.length).to be >= 2
    end

    it 'renders entity names as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts).not_to be_empty
      entity_names = texts.map(&:content)
      expect(entity_names).to include('CUSTOMER')
      expect(entity_names).to include('ORDER')
    end

    it 'renders attributes with key type markers' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      attr_texts = texts.map(&:content).grep(/PK|FK/)
      expect(attr_texts).not_to be_empty
      expect(attr_texts.any? { |t| t.include?('PK') }).to be true
    end

    it 'renders entity separators' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('entity-')
      end

      lines = groups.flat_map(&:children).grep(Sirena::Svg::Line)

      expect(lines).not_to be_empty
    end

    it 'renders relationships' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      expect(groups).not_to be_empty
      expect(groups.length).to eq(1)
    end

    it 'renders relationship lines' do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      lines = rel_groups.flat_map(&:children).grep(Sirena::Svg::Line)

      expect(lines).not_to be_empty
    end

    it 'renders cardinality markers' do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      # Check for circles (zero marker) and lines (cardinality markers)
      elements = rel_groups.flat_map(&:children)
      has_cardinality = elements.any? do |e|
        e.is_a?(Sirena::Svg::Circle) || e.is_a?(Sirena::Svg::Line)
      end

      expect(has_cardinality).to be true
    end

    it 'renders relationship labels' do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      texts = rel_groups.flat_map(&:children).grep(Sirena::Svg::Text)

      label_texts = texts.map(&:content)
      expect(label_texts).to include('places')
    end

    context 'with a graph that has no entities and no relationships' do
      let(:empty_graph) { { id: 'er_diagram', children: [], edges: [] } }

      # Only the 16x16 extent comes from mermaid. mmdc emits
      # viewBox="-8 -8 16 16" here, from centring a zero-size bounding box;
      # Sirena keeps the "0 0" origin all its other diagrams use.
      it 'matches the 16x16 extent mermaid gives an empty ER diagram' do
        svg = renderer.render(empty_graph)

        expect(svg.width).to eq(16)
        expect(svg.height).to eq(16)
        expect(svg.view_box).to eq('0 0 16 16')
        expect(svg.children).to eq([])
      end
    end

    context 'with entities but no relationships' do
      let(:entity_only_graph) do
        { id: 'er_diagram', children: [graph[:children].first], edges: [] }
      end

      # A diagram with entities and no relationships is the ordinary case.
      # It must keep its content size, so the empty check needs both keys to
      # be empty, not either one.
      it 'draws the entities at content size, not the empty canvas' do
        svg = renderer.render(entity_only_graph)

        expect(svg.width).to eq(270)
        expect(svg.height).to eq(210)
        expect(svg.children.map(&:id)).to eq(['entity-CUSTOMER'])
      end
    end

    context 'with a graph whose collection keys are absent' do
      it 'keeps the no-content defaults rather than the empty canvas' do
        svg = renderer.render({ id: 'er_diagram' })

        expect(svg.width).to eq(840)
        expect(svg.height).to eq(640)
      end

      # A default-valued Hash answers `[]` to a lookup while holding no key
      # at all. Absent keys are an unknown shape, not an empty diagram, so
      # these keep the no-content defaults.
      it 'is not fooled by a Hash that defaults its lookups to empty' do
        defaulted = -> { Hash.new { [] }.merge!(id: 'er_diagram') }
        neither = defaulted.call
        children_only = defaulted.call.merge!(children: [])
        edges_only = defaulted.call.merge!(edges: [])

        sizes = [neither, children_only, edges_only].map do |graph|
          svg = renderer.render(graph)
          [svg.width, svg.height]
        end

        expect(sizes).to eq([[880, 680], [880, 680], [880, 680]])
      end
    end

    describe 'classDef styles' do
      def entity_node(id, classes: [], attributes: [])
        {
          id: id, x: 0, y: 0, width: 150, height: 100,
          metadata: { name: id, classes: classes, attributes: attributes }
        }
      end

      def rect_for(svg, entity_id)
        svg.children.find { |c| c.id == "entity-#{entity_id}" }
          .children.grep(Sirena::Svg::Rect).first
      end

      it 'applies a class fill; an unclassed entity keeps the default (C1)' do
        classed_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a']),
                     entity_node('OTHER')],
          edges: [],
          class_defs: { 'a' => 'fill:#f96' }
        }
        svg = renderer.render(classed_graph)

        expect(rect_for(svg, 'CAR').fill).to eq('#f96')
        expect(rect_for(svg, 'OTHER').fill).to eq('#f9f9f9')
      end

      # Resolves classes BY NAME, not by position in the class list — an
      # index-keyed implementation passes every OTHER example here and is
      # only killed by this one plus D1's PERSON-fill clause.
      it 'merges two classes, later wins only on a conflict (C2)' do
        classed_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: %w[a b])],
          edges: [],
          class_defs: { 'a' => 'fill:#111,stroke:#0a0', 'b' => 'fill:#222' }
        }
        svg = renderer.render(classed_graph)
        rect = rect_for(svg, 'CAR')

        expect(rect.fill).to eq('#222')
        expect(rect.stroke).to eq('#0a0')
      end

      it 'applies color to this entity, and not another one (C3)' do
        classed_graph = {
          id: 'er_diagram',
          children: [
            entity_node('CAR', classes: ['a'], attributes: [{ name: 'make' }]),
            entity_node('OTHER', attributes: [{ name: 'x' }])
          ],
          edges: [],
          class_defs: { 'a' => 'color:blue' }
        }
        svg = renderer.render(classed_graph)

        car_texts = svg.children.find { |c| c.id == 'entity-CAR' }
          .children.grep(Sirena::Svg::Text)
        other_texts = svg.children.find { |c| c.id == 'entity-OTHER' }
          .children.grep(Sirena::Svg::Text)

        expect(car_texts.map(&:fill).uniq).to eq(['blue'])
        expect(other_texts.map(&:fill).uniq).to eq(['#000000'])
        expect(rect_for(svg, 'CAR').fill).to eq('#f9f9f9')
      end

      # Order (ghost, known) is load-bearing: an abort-on-first-unknown
      # implementation dies on "ghost" before reaching "known" and this
      # mutant survives if the order is ever reversed.
      it 'ignores an undeclared class without aborting the rest (C4)' do
        classed_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: %w[ghost known])],
          edges: [],
          class_defs: { 'known' => 'fill:#0f0' }
        }
        svg = renderer.render(classed_graph)

        expect(rect_for(svg, 'CAR').fill).to eq('#0f0')
      end

      it 'applies stroke and stroke-width (C5)' do
        classed_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'stroke:#333,stroke-width:4px' }
        }
        svg = renderer.render(classed_graph)
        rect = rect_for(svg, 'CAR')

        expect(rect.stroke).to eq('#333')
        expect(rect.stroke_width).to eq('4px')
      end

      it 'resolves a property key with surrounding space (C6)' do
        classed_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => ' fill : #f96' }
        }
        svg = renderer.render(classed_graph)

        expect(rect_for(svg, 'CAR').fill).to eq('#f96')
      end

      it 'resolves a spaced value, trimmed (C7)' do
        classed_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'fill: #f96' }
        }
        svg = renderer.render(classed_graph)

        expect(rect_for(svg, 'CAR').fill).to eq('#f96')
      end

      # Both "foo" and "font-family:Arial,sans-serif" parse under mermaid.
      # A colon-less chunk must render, not raise.
      #
      # A whole-file revert to base cannot exercise this: base never calls
      # parse_declaration at all, so it neither raises nor differs from the
      # fixed behaviour here, and mutation-check.sh correctly reports STAYED
      # GREEN. Verified against the actual regression instead, by hand: with
      # `next unless value` removed from parse_declaration, this example
      # raises NoMethodError; restored, it passes. Keep it.
      it 'renders a colon-less style chunk instead of raising (C9)' do
        no_colon_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'foo' }
        }
        multi_value_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'font-family:Arial,sans-serif' }
        }

        expect { renderer.render(no_colon_graph) }.not_to raise_error
        expect { renderer.render(multi_value_graph) }.not_to raise_error
        expect(rect_for(renderer.render(no_colon_graph), 'CAR').fill)
          .to eq('#f9f9f9')
        expect(rect_for(renderer.render(multi_value_graph), 'CAR').fill)
          .to eq('#f9f9f9')
      end

      # Verified against mermaid's own bundle and a real browser: its
      # `styles2Map` does `style.split(":")` with no limit and destructures
      # only the first two parts, so `fill:red:blue` resolves to plain
      # `red` and Chrome computes red from mermaid's own output — the
      # `:blue` segment is dropped, never folded into the value.
      it 'discards everything after the second colon in a value (C10)' do
        classed_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'fill:#f96:extra' }
        }
        svg = renderer.render(classed_graph)

        expect(rect_for(svg, 'CAR').fill).to eq('#f96')
      end

      # Verified against mermaid's own db: every entity's cssClasses opens
      # with the literal "default", assigned or not.
      it 'applies the implicit default class even with no assignment (C11)' do
        default_graph = {
          id: 'er_diagram',
          children: [entity_node('CAR')],
          edges: [],
          class_defs: { 'default' => 'fill:red' }
        }
        svg = renderer.render(default_graph)

        expect(rect_for(svg, 'CAR').fill).to eq('red')
      end

      it 'lets an explicit class override a conflicting default property (C12)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'default' => 'fill:red,stroke:green', 'a' => 'fill:blue' }
        }
        svg = renderer.render(graph)
        rect = rect_for(svg, 'CAR')

        expect(rect.fill).to eq('blue')
        expect(rect.stroke).to eq('green')
      end

      # Verified against mermaid's own db: cssClasses is "default a b a" for
      # `CAR:::a,b` then `CAR:::a` — the repeat is NOT deduped, so it moves
      # "a" to the end and lets it win over the intervening "b".
      it 'lets a later duplicate assignment win over an intervening class (C13)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: %w[a b a])],
          edges: [],
          class_defs: { 'a' => 'fill:red', 'b' => 'fill:blue' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('red')
      end

      # Verified against mermaid's own db and a real browser: mermaid stores
      # "FILL:red" verbatim, case untouched, and the browser applies it
      # anyway (getComputedStyle -> rgb(255, 0, 0)) because CSS property
      # names are case-insensitive. Sirena has no CSS engine and must fold
      # the case itself before looking a property up.
      it 'matches a classDef property name regardless of case (C14)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'FILL:red' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('red')
      end

      it 'merges mixed-case property names from different classes (C15)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: %w[a b])],
          edges: [],
          class_defs: { 'a' => 'fill:green', 'b' => 'FILL:red' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('red')
      end

      # Verified against mermaid's own bundle and a real browser: mermaid
      # emits "fill:green !important;FILL:blue !important" for this exact
      # declaration (its own Map collapses the two "fill" chunks in place,
      # keeping "FILL" as a distinct later entry), and Chrome computes blue
      # from that, not green. A parse-time downcase collapses all three
      # chunks into one Ruby key and makes the LAST literal chunk win
      # instead, giving green — this is the regression box_style fixes.
      it 'resolves same-property mixed-case conflicts in source order, not literal-last (C16)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'fill:red,FILL:blue,fill:green' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('blue')
      end

      # Verified against mermaid's own bundle: isLabelStyle
      # (handDrawnShapeStyles.ts) checks `key === "color"`, exact case, so
      # an uppercase COLOR is routed as a box style and never reaches the
      # text label at all. A parse-time downcase folds COLOR into the same
      # Ruby key a real lowercase `color:` would use, so a caller reading
      # text color picks it up and colours the entity name red — this is
      # the wrong-element regression box_style (and the exact-case
      # `styles['color']` reads) fix.
      it 'does not let an uppercase COLOR style the entity name (C17)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'], attributes: [{ name: 'make' }])],
          edges: [],
          class_defs: { 'a' => 'fill:currentColor,COLOR:red' }
        }
        svg = renderer.render(graph)

        car_texts = svg.children.find { |c| c.id == 'entity-CAR' }
          .children.grep(Sirena::Svg::Text)

        expect(car_texts.map(&:fill).uniq).to eq(['#000000'])
      end

      # Verified by Codex against the installed mermaid 11.16.1 bundle and a
      # real browser: an attributed entity's outer box is NOT drawn through
      # the same code path a bare entity's is, and does not go through the
      # browser's case-insensitive CSS cascade at all — it reads only the
      # exact lowercase `fill` key directly. The same class on a bare
      # entity resolves this to blue (C16); here it resolves to green,
      # because `FILL:blue` is invisible to this path.
      it 'resolves fill by exact lowercase key on an attributed entity (C18)' do
        graph = {
          id: 'er_diagram',
          children: [
            entity_node('CAR', classes: ['a'], attributes: [{ name: 'make' }])
          ],
          edges: [],
          class_defs: { 'a' => 'fill:red,FILL:blue,fill:green' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('green')
      end

      # Verified against mermaid's own db (ErDB#addClass): any chunk whose
      # text contains the substring "color" is replayed a second time at
      # the end of its class's declarations, so it wins over a LATER
      # same-property chunk that does not itself mention "color".
      # `stroke:currentcolor,stroke:red` resolves to currentcolor, not the
      # textually-later red.
      #
      # The replay is universal; what differs is whether the copy still
      # names the same property. mermaid renames a lowercase `fill` copy to
      # `bgFill`, so it stops colliding -- see C24. `stroke` is not renamed,
      # which is what this example pins.
      it 'replays a colour-bearing chunk after a later same-property one (C19)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'stroke:currentcolor,stroke:red' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').stroke).to eq('currentcolor')
      end

      # mermaid appends its `textStyles` replay after the class's own
      # styles, so a replayed chunk lands last among same-key entries. It
      # defuses that for `fill` by RENAMING the replayed copy to `bgFill`,
      # which no longer collides with the box. Executing mermaid's own db
      # API returns `textStyles: ["bgFill:currentcolor", "FILL:currentcolor",
      # "stroke:currentcolor"]` -- lowercase rewritten, `FILL` left alone.
      #
      # So the exemption is exact-lowercase, and the two mixed-case
      # examples below are the ones that pin that. An earlier fix folded
      # the key and silently changed `FILL` from currentcolor to blue;
      # nothing in the suite caught it.
      it 'does not replay a colour-bearing FILL over a later one (C24)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'fill:currentcolor,fill:blue' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('blue')
      end

      %w[FILL FiLl].each do |key|
        it "still replays a #{key} chunk, which mermaid does not rename (C25 #{key})" do
          graph = {
            id: 'er_diagram',
            children: [entity_node('CAR', classes: ['a'])],
            edges: [],
            class_defs: { 'a' => "#{key}:currentcolor,#{key}:blue" }
          }
          svg = renderer.render(graph)

          expect(rect_for(svg, 'CAR').fill).to eq('currentcolor')
        end
      end

      # Verified by Codex against the installed mermaid 11.16.1 bundle and
      # a real Chrome computation: an attributed entity's stroke and
      # stroke-width read the same exact-case Map fill does (C18), not
      # the case-insensitive cascade — this declaration computes
      # green/4px attributed, where C16's bare fill equivalent computes
      # blue/8px.
      it 'resolves stroke and stroke-width by exact lowercase key on an attributed entity (C20)' do
        graph = {
          id: 'er_diagram',
          children: [
            entity_node('CAR', classes: ['a'], attributes: [{ name: 'make' }])
          ],
          edges: [],
          class_defs: { 'a' => 'stroke:red,STROKE:blue,stroke:green,' \
                                'stroke-width:2px,STROKE-WIDTH:8px,stroke-width:4px' }
        }
        svg = renderer.render(graph)
        rect = rect_for(svg, 'CAR')

        expect(rect.stroke).to eq('green')
        expect(rect.stroke_width).to eq('4px')
      end

      # Verified against a real browser: mermaid emits
      # "fill:currentColor !important;COLOR:red !important" for a bare
      # entity's box, and the browser's `color` cascade resolves
      # currentColor to red. Sirena has no cascade left to replay at
      # paint time, so it must substitute the concrete value now.
      it 'resolves currentColor against an ambient COLOR override on a bare entity (C21)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'fill:currentColor,COLOR:red' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('red')
      end

      # Ruby's default String#split drops a trailing empty field, so
      # "fill:".split(':') read as "no colon" and this value-clearing
      # declaration was silently ignored, leaving the stale earlier
      # "red". Mermaid's own JS split keeps it, and the browser drops
      # the resulting empty CSS declaration, computing its default.
      it 'lets a trailing empty value clear an earlier declaration (C22)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'fill:red,fill:' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('#f9f9f9')
      end

      # Verified against a real browser: Chrome rejects "bogus" as an
      # invalid <color>, drops that declaration entirely during
      # cascade, and computes red from the earlier valid "fill:red" —
      # not black from "bogus".
      it 'keeps an earlier valid value when a later same-property one is invalid CSS (C23)' do
        graph = {
          id: 'er_diagram',
          children: [entity_node('CAR', classes: ['a'])],
          edges: [],
          class_defs: { 'a' => 'fill:red,FILL:bogus' }
        }
        svg = renderer.render(graph)

        expect(rect_for(svg, 'CAR').fill).to eq('red')
      end
    end
  end
end
