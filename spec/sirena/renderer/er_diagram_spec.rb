# frozen_string_literal: true

require "spec_helper"

# Pure fixture/lookup helpers, single-user (this file only): module_function
# so they can be called at describe-body level to generate examples.
module ErDiagramSpecHelpers
  TRACKED_HOOKS = %i[
    calculate_width calculate_height render_entities render_entity
    render_entity_content render_attribute render_relationships
    render_relationship calculate_connection_point render_relationship_line
    render_cardinality render_relationship_label
  ].freeze
  HOOK_ARITIES = {
    calculate_width: 1, calculate_height: 1, render_entities: 2,
    render_entity: 2, render_entity_content: 3, render_attribute: 5,
    render_relationships: 2, render_relationship: 3, find_node: 2,
    calculate_connection_point: 2, render_relationship_line: 4,
    render_cardinality: 5, render_one_marker: 3,
    render_zero_or_more_marker: 3, render_one_or_more_marker: 3,
    render_zero_or_one_marker: 3, render_circle_marker: 3,
    render_crows_foot: 3, render_relationship_label: 4
  }.freeze
  RELATIONSHIP_HOOK_SNAPSHOT = [
    { x: 100, y: 25 },
    [1, 1, 1, 4, 4, 2, 1, 3, 1],
    "12",
  ].freeze
  ROUTED_SECTIONS = [
    {
      startPoint: { x: 30, y: 200 },
      bendPoints: [{ x: 80, y: 200 }],
      endPoint: { x: 120, y: 220 },
    },
    {
      start_point: { x: 120, y: 220 },
      bend_points: [],
      end_point: { x: 330, y: 220 },
    },
  ].freeze
  ROUTED_SNAPSHOT = [
    [
      [[30.0, 200.0], [[80.0, 200.0]], [120.0, 220.0]],
      [[120.0, 220.0], [], [330.0, 220.0]],
    ],
    [Sirena::Svg::Path, "M 30.0 200.0 L 80.0 200.0 L 120.0 220.0"],
    [Sirena::Svg::Line, 120.0, 220.0, 330.0, 220.0],
    [30.0, 207.0, 30.0, 193.0],
    [323.0, 220.0],
  ].freeze

  module_function

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

  def entity_elements(svg, element_class)
    svg.children.select { |child| child.id&.start_with?("entity-") }
      .flat_map(&:children).grep(element_class)
  end

  # `#content` is a `collection: true` attribute (see `Svg::Text#simple_body`);
  # which lutaml-model version is loaded determines whether a scalar
  # assignment reads back as a scalar or a one-element Array. Always read it
  # through this helper, the same way production code does
  # (`Array(content).join`), never raw `#content`.
  def svg_text_content(element)
    Array(element.content).join
  end

  def graph_hook_snapshot(renderer, graph)
    scene = Sirena::Layout::ErDiagram.from_graph(graph)
    svg = renderer.send(:document, scene)
    renderer.send(:render_relationships, graph, svg)
    renderer.send(:render_entities, graph, svg)
    texts = svg.children.flat_map(&:children).grep(Sirena::Svg::Text)
    [texts.map { |text| svg_text_content(text) }, svg.children.map(&:id),
     svg.to_xml, renderer.render(scene).to_xml]
  end

  def public_hook_calls(renderer_class, graph)
    calls = Hash.new(0)
    tracker = hook_tracking_renderer(renderer_class, calls)
    tracker.render(graph)
    calls
  end

  def routed_snapshot(renderer, graph)
    graph[:edges].first[:sections] = ROUTED_SECTIONS
    scene = Sirena::Layout::ErDiagram.from_graph(graph)
    edge = scene.edges.first
    first, second = renderer.render(scene).children.first.children.first(2)
    [section_snapshot(edge), *shape_snapshot(first, second),
     *marker_snapshot(edge)]
  end

  def section_snapshot(edge)
    edge.sections.map do |section|
      [point_snapshot(section.start_point),
       section.bend_points.map { |point| point_snapshot(point) },
       point_snapshot(section.end_point)]
    end
  end

  def point_snapshot(point)
    [point.x, point.y]
  end

  def shape_snapshot(first, second)
    [[first.class, first.d],
     [second.class, second.x1, second.y1, second.x2, second.y2]]
  end

  def marker_snapshot(edge)
    line = edge.source_marker.lines.first
    circle = edge.target_marker.circles.first
    [[line.x1, line.y1, line.x2, line.y2], [circle.cx, circle.cy]]
  end

  def hook_arities(renderer)
    HOOK_ARITIES.keys.to_h { |name| [name, renderer.method(name).arity] }
  end

  def entity_hook_snapshot(renderer, node)
    entity_svg = Sirena::Svg::Document.new
    renderer.send(:render_entity, node, entity_svg)
    content = Sirena::Svg::Group.new
    renderer.send(:render_entity_content, node, node[:metadata], content)
    attribute = Sirena::Svg::Group.new
    next_y = render_first_attribute(renderer, node, attribute)
    [entity_svg.children.length, content.children.length,
     attribute.children.length, next_y]
  end

  def graph_hooks_observed?(renderer, graph)
    contents, ids, compatibility_xml, scene_xml =
      graph_hook_snapshot(renderer, graph)
    (%w[places PK\ int\ id string\ name] - contents).empty? &&
      ids == %w[rel-CUSTOMER_to_ORDER entity-CUSTOMER entity-ORDER] &&
      compatibility_xml == scene_xml
  end

  def relationship_hook_snapshot(renderer)
    point = { x: 100, y: 25 }
    opposite = { x: 200, y: 25 }
    groups = Array.new(9) { Sirena::Svg::Group.new }
    emit_relationship_hooks(renderer, point, opposite, groups)
    connection = renderer.send(:calculate_connection_point,
                               { x: 0, y: 0, width: 100, height: 50 },
                               { x: 200, y: 0, width: 100, height: 50 })
    [connection, groups.map { |group| group.children.length },
     groups.last.children.first.font_size]
  end

  def extent_hook_snapshot(renderer, graph)
    [renderer.send(:find_node, graph, "ORDER")[:id],
     renderer.send(:find_node, graph, nil),
     renderer.send(:calculate_width, graph),
     renderer.send(:calculate_height, graph),
     renderer.send(:calculate_width, children: [], edges: []),
     renderer.send(:calculate_height, children: [], edges: []),
     renderer.send(:calculate_width, children: []),
     renderer.send(:calculate_height, children: [])]
  end

  def hook_tracking_renderer(renderer_class, calls)
    Class.new(renderer_class) do
      protected

      TRACKED_HOOKS.each do |name|
        define_method(name) do |*arguments|
          calls[name] += 1
          super(*arguments)
        end
      end
    end.new
  end

  def render_first_attribute(renderer, node, group)
    attribute = node[:metadata][:attributes].first
    renderer.send(:render_attribute, 10, 20, 180, attribute, group)
  end

  def emit_relationship_hooks(renderer, point, opposite, groups)
    renderer.send(:render_relationship_line, point, opposite,
                  "non-identifying", groups[0])
    renderer.send(:render_cardinality, point, opposite, "one", nil, groups[1])
    %i[render_one_marker render_zero_or_more_marker render_one_or_more_marker
       render_zero_or_one_marker render_circle_marker render_crows_foot]
      .each_with_index do |name, index|
        renderer.send(name, point, opposite, groups[index + 2])
      end
    renderer.send(:render_relationship_label, { labels: [{ text: "places" }] },
                  point, opposite, groups[8])
  end
end

RSpec.describe Sirena::Renderer::ErDiagram do
  include ErDiagramSpecHelpers

  let(:renderer) { described_class.new }

  describe "#render" do
    let(:graph) do
      {
        id: "er_diagram",
        children: [
          {
            id: "CUSTOMER",
            x: 10,
            y: 10,
            width: 180,
            height: 120,
            labels: [{ text: "CUSTOMER", width: 80, height: 16 }],
            metadata: {
              name: "CUSTOMER",
              attributes: [
                { name: "id", attribute_type: "int", key_type: "PK" },
                { name: "name", attribute_type: "string", key_type: nil },
              ],
            },
          },
          {
            id: "ORDER",
            x: 250,
            y: 10,
            width: 180,
            height: 100,
            labels: [{ text: "ORDER", width: 60, height: 16 }],
            metadata: {
              name: "ORDER",
              attributes: [
                { name: "order_id", attribute_type: "int", key_type: "PK" },
              ],
            },
          },
        ],
        edges: [
          {
            id: "CUSTOMER_to_ORDER",
            sources: ["CUSTOMER"],
            targets: ["ORDER"],
            labels: [{ text: "places" }],
            metadata: {
              relationship_type: "non-identifying",
              cardinality_from: "one",
              cardinality_to: "zero_or_more",
            },
          },
        ],
      }
    end

    it "renders graph to SVG document" do
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it "includes entity boxes in SVG" do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("entity-")
      end
      expect(groups.length).to eq(2)
    end

    it "renders entity boxes as rectangles" do
      rects = ErDiagramSpecHelpers.entity_elements(
        renderer.render(graph), Sirena::Svg::Rect
      )
      expect(rects.length).to be >= 2
    end

    it "renders entity names as text elements" do
      texts = ErDiagramSpecHelpers.entity_elements(
        renderer.render(graph), Sirena::Svg::Text
      )
      names = texts.map { |text| svg_text_content(text) }
      expect(names).to include("CUSTOMER", "ORDER")
    end

    it "renders attributes with key type markers" do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("entity-")
      end

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      attr_texts = texts.map { |t| Array(t.content).join }.grep(/PK|FK/)
      expect(attr_texts).not_to be_empty
      expect(attr_texts.any? { |t| t.include?("PK") }).to be true
    end

    # Asserts the note TEXT reaches the SVG, not merely that a note node
    # survived the parser -- the layout and renderer layers each have a
    # place to silently drop it before it becomes visible.
    it "renders the attribute note text" do
      graph[:children].first[:metadata][:attributes].first[:note] = "NN"

      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("entity-")
      end
      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts.map { |t| svg_text_content(t) })
        .to include(a_string_matching(/\bNN\b/))
    end

    # Keep this: it is the only check that the `attribute[:note] &&` half of
    # the guard on er_diagram.rb's attr line still holds, since
    # mutation-check.sh's whole-file-revert cannot score it (a reverted file
    # has no note handling, so an absent note renders the same either way).
    it "omits the note segment when no note is present" do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("entity-")
      end
      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)
      attr_line = texts.map { |t| svg_text_content(t) }
        .find { |text| text.include?("id") }

      expect(attr_line).to eq("PK int id")
    end

    # Keep this: it is the only check that the `!attribute[:note].empty?`
    # half of the same guard still holds, since mutation-check.sh's revert
    # cannot score it either (absent vs. empty note renders identically
    # whether or not the note feature exists at all).
    it "omits the note segment when the note is an empty string" do
      graph[:children].first[:metadata][:attributes].first[:note] = ""

      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("entity-")
      end
      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)
      attr_line = texts.map { |t| svg_text_content(t) }.find { |t| t.include?("id") }

      expect(attr_line).to eq("PK int id")
    end

    it "renders entity separators" do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("entity-")
      end

      lines = groups.flat_map(&:children).grep(Sirena::Svg::Line)

      expect(lines).not_to be_empty
    end

    it "renders relationships" do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("rel-")
      end

      expect(groups).not_to be_empty
      expect(groups.length).to eq(1)
    end

    it "renders relationship lines" do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("rel-")
      end

      lines = rel_groups.flat_map(&:children).grep(Sirena::Svg::Line)

      expect(lines).not_to be_empty
    end

    it "preserves and renders every routed section" do
      expect(ErDiagramSpecHelpers.routed_snapshot(renderer, graph))
        .to eq(ErDiagramSpecHelpers::ROUTED_SNAPSHOT)
    end

    it "does not synthesize a route for supplied empty sections" do
      graph[:edges].first[:sections] = []
      scene = Sirena::Layout::ErDiagram.from_graph(graph)
      expect(scene.edges.first.sections).to eq([])
    end

    it "renders cardinality markers" do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("rel-")
      end

      # Check for circles (zero marker) and lines (cardinality markers)
      elements = rel_groups.flat_map(&:children)
      has_cardinality = elements.any? do |e|
        e.is_a?(Sirena::Svg::Circle) || e.is_a?(Sirena::Svg::Line)
      end

      expect(has_cardinality).to be true
    end

    it "renders relationship labels" do
      svg = renderer.render(graph)

      rel_groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("rel-")
      end

      texts = rel_groups.flat_map(&:children).grep(Sirena::Svg::Text)

      label = texts.find { |text| Array(text.content).join == "places" }
      expect([Array(label.content).join, label.font_size]).to eq(["places", "12"])
    end

    it "emits every text role at its injected theme size" do
      theme = Sirena::Theme::Registry.get(:high_contrast)
      renderer.theme = theme
      scene = Sirena::Layout::ErDiagram.from_graph(graph, theme: theme)
      texts = renderer.render(scene).children.flat_map(&:children)
        .grep(Sirena::Svg::Text)
      sizes = texts.to_h do |text|
        [ErDiagramSpecHelpers.svg_text_content(text), text.font_size]
      end

      expect(sizes.slice("CUSTOMER", "PK int id", "places"))
        .to eq("CUSTOMER" => "18", "PK int id" => "14", "places" => "14")
    end

    it "preserves the released protected hook names and arities" do
      expect(ErDiagramSpecHelpers.hook_arities(renderer))
        .to eq(ErDiagramSpecHelpers::HOOK_ARITIES)
    end

    it "keeps the released graph rendering hooks observable" do
      expect(ErDiagramSpecHelpers.graph_hooks_observed?(renderer, graph))
        .to be true
    end

    it "dispatches public Hash rendering through the released hooks" do
      expect(ErDiagramSpecHelpers.public_hook_calls(described_class, graph)).to eq(
        calculate_width: 1, calculate_height: 1,
        render_relationships: 1, render_relationship: 1,
        calculate_connection_point: 2,
        render_relationship_line: 1, render_cardinality: 2,
        render_relationship_label: 1, render_entities: 1, render_entity: 2,
        render_entity_content: 2, render_attribute: 3
      )
    end

    it "dispatches typed Scene rendering through the released hooks" do
      scene = Sirena::Layout::ErDiagram.from_graph(graph)

      expect(ErDiagramSpecHelpers.public_hook_calls(described_class, scene))
        .to eq(render_relationships: 1, render_entities: 1)
    end

    it "keeps the released entity hooks observable" do
      snapshot = ErDiagramSpecHelpers.entity_hook_snapshot(
        renderer, graph[:children].first
      )
      expect(snapshot).to eq([1, 4, 1, 38])
    end

    it "keeps the released relationship geometry hooks observable" do
      expect(ErDiagramSpecHelpers.relationship_hook_snapshot(renderer))
        .to eq(ErDiagramSpecHelpers::RELATIONSHIP_HOOK_SNAPSHOT)
    end

    it "keeps released lookup and extent hooks observable" do
      expect(ErDiagramSpecHelpers.extent_hook_snapshot(renderer, graph)).to eq(
        ["ORDER", nil, 470, 170, 0, 0, 840, 640],
      )
    end

    context "with a graph that has no entities and no relationships" do
      let(:empty_graph) { { id: "er_diagram", children: [], edges: [] } }

      # Only the 16x16 extent comes from mermaid. mmdc emits
      # viewBox="-8 -8 16 16" here, from centring a zero-size bounding box;
      # Sirena keeps the "0 0" origin all its other diagrams use.
      it "matches the 16x16 extent mermaid gives an empty ER diagram" do
        svg = renderer.render(empty_graph)

        expect(svg.width).to eq(16)
        expect(svg.height).to eq(16)
        expect(svg.view_box).to eq("0 0 16 16")
        expect(svg.children).to eq([])
      end
    end

    context "with entities but no relationships" do
      let(:entity_only_graph) do
        { id: "er_diagram", children: [graph[:children].first], edges: [] }
      end

      # A diagram with entities and no relationships is the ordinary case.
      # It must keep its content size, so the empty check needs both keys to
      # be empty, not either one.
      it "draws the entities at content size, not the empty canvas" do
        svg = renderer.render(entity_only_graph)

        expect(svg.width).to eq(270)
        expect(svg.height).to eq(210)
        expect(svg.children.map(&:id)).to eq(["entity-CUSTOMER"])
      end
    end

    context "with a graph whose collection keys are absent" do
      it "keeps the no-content defaults rather than the empty canvas" do
        svg = renderer.render({ id: "er_diagram" })

        expect(svg.width).to eq(840)
        expect(svg.height).to eq(640)
      end

      # A default-valued Hash answers `[]` to a lookup while holding no key
      # at all. Absent keys are an unknown shape, not an empty diagram, so
      # these keep the no-content defaults.
      it "is not fooled by a Hash that defaults its lookups to empty" do
        defaulted = -> { Hash.new { [] }.merge!(id: "er_diagram") }
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

    describe "classDef styles" do
      it "applies a class fill; an unclassed entity keeps the default (C1)" do
        classed_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"]),
                     ErDiagramSpecHelpers.entity_node("OTHER")],
          edges: [],
          class_defs: { "a" => "fill:#f96" },
        }
        svg = renderer.render(classed_graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("#f96")
        expect(ErDiagramSpecHelpers.rect_for(svg, "OTHER").fill).to eq("#f9f9f9")
      end

      # Resolves classes BY NAME, not by position in the class list — an
      # index-keyed implementation passes every OTHER example here and is
      # only killed by this one plus D1's PERSON-fill clause.
      it "merges two classes, later wins only on a conflict (C2)" do
        classed_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: %w[a b])],
          edges: [],
          class_defs: { "a" => "fill:#111,stroke:#0a0", "b" => "fill:#222" },
        }
        svg = renderer.render(classed_graph)
        rect = ErDiagramSpecHelpers.rect_for(svg, "CAR")

        expect(rect.fill).to eq("#222")
        expect(rect.stroke).to eq("#0a0")
      end

      it "applies color to this entity, and not another one (C3)" do
        classed_graph = {
          id: "er_diagram",
          children: [
            ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"], attributes: [{ name: "make" }]),
            ErDiagramSpecHelpers.entity_node("OTHER", attributes: [{ name: "x" }]),
          ],
          edges: [],
          class_defs: { "a" => "color:blue" },
        }
        svg = renderer.render(classed_graph)

        car_texts = svg.children.find { |c| c.id == "entity-CAR" }
          .children.grep(Sirena::Svg::Text)
        other_texts = svg.children.find { |c| c.id == "entity-OTHER" }
          .children.grep(Sirena::Svg::Text)

        expect(car_texts.map(&:fill).uniq).to eq(["blue"])
        expect(other_texts.map(&:fill).uniq).to eq(["#000000"])
        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("#f9f9f9")
      end

      # Order (ghost, known) is load-bearing: an abort-on-first-unknown
      # implementation dies on "ghost" before reaching "known" and this
      # mutant survives if the order is ever reversed.
      it "ignores an undeclared class without aborting the rest (C4)" do
        classed_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: %w[ghost known])],
          edges: [],
          class_defs: { "known" => "fill:#0f0" },
        }
        svg = renderer.render(classed_graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("#0f0")
      end

      it "applies stroke and stroke-width (C5)" do
        classed_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "stroke:#333,stroke-width:4px" },
        }
        svg = renderer.render(classed_graph)
        rect = ErDiagramSpecHelpers.rect_for(svg, "CAR")

        expect(rect.stroke).to eq("#333")
        expect(rect.stroke_width).to eq("4px")
      end

      it "resolves a property key with surrounding space (C6)" do
        classed_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => " fill : #f96" },
        }
        svg = renderer.render(classed_graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("#f96")
      end

      it "resolves a spaced value, trimmed (C7)" do
        classed_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "fill: #f96" },
        }
        svg = renderer.render(classed_graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("#f96")
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
      it "renders a colon-less style chunk instead of raising (C9)" do
        no_colon_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "foo" },
        }
        multi_value_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "font-family:Arial,sans-serif" },
        }

        expect { renderer.render(no_colon_graph) }.not_to raise_error
        expect { renderer.render(multi_value_graph) }.not_to raise_error
        expect(ErDiagramSpecHelpers.rect_for(renderer.render(no_colon_graph), "CAR").fill)
          .to eq("#f9f9f9")
        expect(ErDiagramSpecHelpers.rect_for(renderer.render(multi_value_graph), "CAR").fill)
          .to eq("#f9f9f9")
      end

      # Verified against mermaid's own bundle and a real browser: its
      # `styles2Map` does `style.split(":")` with no limit and destructures
      # only the first two parts, so `fill:red:blue` resolves to plain
      # `red` and Chrome computes red from mermaid's own output — the
      # `:blue` segment is dropped, never folded into the value.
      it "discards everything after the second colon in a value (C10)" do
        classed_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "fill:#f96:extra" },
        }
        svg = renderer.render(classed_graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("#f96")
      end

      # Verified against mermaid's own db: every entity's cssClasses opens
      # with the literal "default", assigned or not.
      it "applies the implicit default class even with no assignment (C11)" do
        default_graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR")],
          edges: [],
          class_defs: { "default" => "fill:red" },
        }
        svg = renderer.render(default_graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("red")
      end

      it "lets an explicit class override a conflicting default property (C12)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "default" => "fill:red,stroke:green", "a" => "fill:blue" },
        }
        svg = renderer.render(graph)
        rect = ErDiagramSpecHelpers.rect_for(svg, "CAR")

        expect(rect.fill).to eq("blue")
        expect(rect.stroke).to eq("green")
      end

      # Verified against mermaid's own db: cssClasses is "default a b a" for
      # `CAR:::a,b` then `CAR:::a` — the repeat is NOT deduped, so it moves
      # "a" to the end and lets it win over the intervening "b".
      it "lets a later duplicate assignment win over an intervening class (C13)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: %w[a b a])],
          edges: [],
          class_defs: { "a" => "fill:red", "b" => "fill:blue" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("red")
      end

      # Verified against mermaid's own db and a real browser: mermaid stores
      # "FILL:red" verbatim, case untouched, and the browser applies it
      # anyway (getComputedStyle -> rgb(255, 0, 0)) because CSS property
      # names are case-insensitive. Sirena has no CSS engine and must fold
      # the case itself before looking a property up.
      it "matches a classDef property name regardless of case (C14)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "FILL:red" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("red")
      end

      it "merges mixed-case property names from different classes (C15)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: %w[a b])],
          edges: [],
          class_defs: { "a" => "fill:green", "b" => "FILL:red" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("red")
      end

      # Verified against mermaid's own bundle and a real browser: mermaid
      # emits "fill:green !important;FILL:blue !important" for this exact
      # declaration (its own Map collapses the two "fill" chunks in place,
      # keeping "FILL" as a distinct later entry), and Chrome computes blue
      # from that, not green. A parse-time downcase collapses all three
      # chunks into one Ruby key and makes the LAST literal chunk win
      # instead, giving green — this is the regression box_style fixes.
      it "resolves same-property mixed-case conflicts in source order, not literal-last (C16)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "fill:red,FILL:blue,fill:green" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("blue")
      end

      # Verified against mermaid's own bundle: isLabelStyle
      # (handDrawnShapeStyles.ts) checks `key === "color"`, exact case, so
      # an uppercase COLOR is routed as a box style and never reaches the
      # text label at all. A parse-time downcase folds COLOR into the same
      # Ruby key a real lowercase `color:` would use, so a caller reading
      # text color picks it up and colours the entity name red — this is
      # the wrong-element regression box_style (and the exact-case
      # `styles['color']` reads) fix.
      it "does not let an uppercase COLOR style the entity name (C17)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"], attributes: [{ name: "make" }])],
          edges: [],
          class_defs: { "a" => "fill:currentColor,COLOR:red" },
        }
        svg = renderer.render(graph)

        car_texts = svg.children.find { |c| c.id == "entity-CAR" }
          .children.grep(Sirena::Svg::Text)

        expect(car_texts.map(&:fill).uniq).to eq(["#000000"])
      end

      # Verified by Codex against the installed mermaid 11.16.1 bundle and a
      # real browser: an attributed entity's outer box is NOT drawn through
      # the same code path a bare entity's is, and does not go through the
      # browser's case-insensitive CSS cascade at all — it reads only the
      # exact lowercase `fill` key directly. The same class on a bare
      # entity resolves this to blue (C16); here it resolves to green,
      # because `FILL:blue` is invisible to this path.
      it "resolves fill by exact lowercase key on an attributed entity (C18)" do
        graph = {
          id: "er_diagram",
          children: [
            ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"], attributes: [{ name: "make" }]),
          ],
          edges: [],
          class_defs: { "a" => "fill:red,FILL:blue,fill:green" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("green")
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
      it "replays a colour-bearing chunk after a later same-property one (C19)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "stroke:currentcolor,stroke:red" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").stroke).to eq("currentcolor")
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
      it "does not replay a colour-bearing FILL over a later one (C24)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "fill:currentcolor,fill:blue" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("blue")
      end

      %w[FILL FiLl].each do |key|
        it "still replays a #{key} chunk, which mermaid does not rename (C25 #{key})" do
          graph = {
            id: "er_diagram",
            children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
            edges: [],
            class_defs: { "a" => "#{key}:currentcolor,#{key}:blue" },
          }
          svg = renderer.render(graph)

          expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("currentcolor")
        end
      end

      # Verified by Codex against the installed mermaid 11.16.1 bundle and
      # a real Chrome computation: an attributed entity's stroke and
      # stroke-width read the same exact-case Map fill does (C18), not
      # the case-insensitive cascade — this declaration computes
      # green/4px attributed, where C16's bare fill equivalent computes
      # blue/8px.
      it "resolves stroke and stroke-width by exact lowercase key on an attributed entity (C20)" do
        graph = {
          id: "er_diagram",
          children: [
            ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"], attributes: [{ name: "make" }]),
          ],
          edges: [],
          class_defs: { "a" => "stroke:red,STROKE:blue,stroke:green," \
                                "stroke-width:2px,STROKE-WIDTH:8px,stroke-width:4px" },
        }
        svg = renderer.render(graph)
        rect = ErDiagramSpecHelpers.rect_for(svg, "CAR")

        expect(rect.stroke).to eq("green")
        expect(rect.stroke_width).to eq("4px")
      end

      # Verified against a real browser: mermaid emits
      # "fill:currentColor !important;COLOR:red !important" for a bare
      # entity's box, and the browser's `color` cascade resolves
      # currentColor to red. Sirena has no cascade left to replay at
      # paint time, so it must substitute the concrete value now.
      it "resolves currentColor against an ambient COLOR override on a bare entity (C21)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "fill:currentColor,COLOR:red" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("red")
      end

      # Ruby's default String#split drops a trailing empty field, so
      # "fill:".split(':') read as "no colon" and this value-clearing
      # declaration was silently ignored, leaving the stale earlier
      # "red". Mermaid's own JS split keeps it, and the browser drops
      # the resulting empty CSS declaration, computing its default.
      it "lets a trailing empty value clear an earlier declaration (C22)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "fill:red,fill:" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("#f9f9f9")
      end

      # Verified against a real browser: Chrome rejects "bogus" as an
      # invalid <color>, drops that declaration entirely during
      # cascade, and computes red from the earlier valid "fill:red" —
      # not black from "bogus".
      it "keeps an earlier valid value when a later same-property one is invalid CSS (C23)" do
        graph = {
          id: "er_diagram",
          children: [ErDiagramSpecHelpers.entity_node("CAR", classes: ["a"])],
          edges: [],
          class_defs: { "a" => "fill:red,FILL:bogus" },
        }
        svg = renderer.render(graph)

        expect(ErDiagramSpecHelpers.rect_for(svg, "CAR").fill).to eq("red")
      end
    end
  end
end
