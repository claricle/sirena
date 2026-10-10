# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

# Pure geometry/XML helpers, single-user (this file only): module_function
# so they can be called at describe-body level to generate examples.
module ClassDiagramSpecHelpers
  module_function

  def rendered_document(source, options = {})
    svg = Sirena::Engine.new.render("classDiagram\n  #{source}\n", options)
    REXML::Document.new(svg)
  end

  def relationship_group(doc, edge_id)
    REXML::XPath.first(doc, "//*[@id='rel-#{edge_id}']")
  end

  def font_size(document, text)
    node = REXML::XPath.match(document, "//text").find do |item|
      item.texts.map(&:value).join == text
    end
    node.attributes["font-size"]
  end

  def font_sizes(document, labels)
    labels.map { |label| font_size(document, label) }
  end

  def method_arities(object, names)
    names.to_h { |name| [name, object.method(name).arity] }
  end

  def theme_font_sizes(document)
    [
      font_size(document, "A"),
      font_sizes(document, %w[«interface» owns 1 many]),
    ]
  end

  def node_rect(doc, node_id)
    REXML::XPath.first(doc, "//*[@id='class-#{node_id}']/rect")
  end

  def polygon_points(element)
    element.attributes["points"].split.map do |point|
      point.split(",").map(&:to_f)
    end
  end

  def rect_bounds(rect)
    x = rect.attributes["x"].to_f
    y = rect.attributes["y"].to_f
    [x, x + rect.attributes["width"].to_f, y,
     y + rect.attributes["height"].to_f]
  end

  def inside_rect?(point, rect)
    x_min, x_max, y_min, y_max = rect_bounds(rect)
    point[0].between?(x_min, x_max) && point[1].between?(y_min, y_max)
  end

  # Which end of the relationship line a marker's polygon sits nearest --
  # read off the real rendered <line>'s own endpoints, never a hardcoded
  # coordinate threshold, so this holds under whatever the fallback grid
  # layout actually placed the two nodes at.
  def nearer_endpoint(points, line)
    center = centroid(points)
    start_distance = distance(center, line_endpoint(line, "1"))
    end_distance = distance(center, line_endpoint(line, "2"))
    start_distance < end_distance ? :start : :end
  end

  def centroid(points)
    [points.sum(&:first) / points.length, points.sum(&:last) / points.length]
  end

  def line_endpoint(line, suffix)
    %w[x y].map { |axis| line.attributes["#{axis}#{suffix}"].to_f }
  end

  def distance(first, second)
    Math.hypot(first[0] - second[0], first[1] - second[1])
  end

  # Composition/aggregation's diamond is a rhombus: all four edges equal
  # length. The dependency dart is deliberately asymmetric (see
  # DART_NEAR/DART_FAR/DART_WIDTH in the renderer) so it reads as a
  # distinct glyph even though both are 4-point filled polygons.
  def rhombus?(points)
    return false unless points.length == 4

    polygon_edge_lengths(points).map { |edge| edge.round(2) }.uniq.one?
  end

  def polygon_edge_lengths(points)
    pairs = points.each_cons(2).to_a << [points.last, points.first]
    pairs.map { |first, second| distance(first, second) }
  end

  # Twice the signed area of triangle a-b-c: zero exactly when a, b, c
  # are collinear.
  def signed_area2(point_a, point_b, point_c)
    ((point_b[0] - point_a[0]) * (point_c[1] - point_a[1])) -
      ((point_c[0] - point_a[0]) * (point_b[1] - point_a[1]))
  end

  # Defect (a) -- degenerate polygon. A filled quadrilateral is not
  # really one if any three of its four vertices sit on one line --
  # deleting the middle one then leaves the drawn area unchanged, i.e.
  # it silently renders as a triangle. mermaid's own dependency marker
  # (`M 5,7 L9,13 L1,7 L9,1 Z`) passes this: every one of its four
  # vertex triples has nonzero signed area. Fewer than 4 points fails
  # outright, same as a degenerate polygon. This is the exact defect an
  # earlier round shipped (Codex, round 4, class_diagram.rb:480).
  def no_three_collinear?(points)
    return false unless points.length == 4

    points.combination(3).all? { |triple| signed_area2(*triple) != 0 }
  end

  def rendered_bent_route(renderer, scene)
    scene.edges.first.sections = [bent_section]
    group = renderer.render(scene).children.find do |item|
      item.id&.start_with?("rel-")
    end
    group.children.grep(Sirena::Svg::Path).first.d
  end

  def bent_section
    section = Sirena::Layout::ClassDiagram::Section
    point = Sirena::Layout::ClassDiagram::Point
    section.new(
      start_point: point.new(x: 100, y: 25),
      end_point: point.new(x: 200, y: 25),
      bend_points: [point.new(x: 150, y: 80)],
    )
  end

  def record_collection_hooks(renderer, calls)
    hooks = Module.new
    %i[render_relationships render_classes].each do |name|
      hooks.define_method(name) do |*args|
        calls << name
        super(*args)
      end
    end
    renderer.singleton_class.prepend(hooks)
  end

  def svg_texts(svg)
    groups = svg.children.grep(Sirena::Svg::Group)
    groups.flat_map(&:children).grep(Sirena::Svg::Text)
      .map { |text| Array(text.content).join }
  end

  def relationship_parts(source)
    doc = rendered_document(source)
    group = relationship_group(doc, "A_to_B")
    [doc, REXML::XPath.first(group, "line"),
     REXML::XPath.match(group, "polygon")]
  end

  def polygon_near(polygons, line, endpoint)
    polygons.find do |polygon|
      nearer_endpoint(polygon_points(polygon), line) == endpoint
    end
  end

  def aggregation_inheritance_summary
    _doc, line, polygons = relationship_parts("A o--|> B")
    diamond = polygons.find { |polygon| polygon_points(polygon).length == 4 }
    triangle = polygons.find { |polygon| polygon_points(polygon).length == 3 }
    [line.attributes["stroke-dasharray"], *marker_summary(diamond, line),
     *marker_summary(triangle, line)]
  end

  def marker_summary(marker, line)
    [marker.attributes["fill"], nearer_endpoint(polygon_points(marker), line)]
  end

  def dependency_composition_summary
    doc, line, polygons = relationship_parts("A <--* B")
    dependency = polygon_near(polygons, line, :start)
    composition = polygon_near(polygons, line, :end)
    dependency_summary(doc, dependency) + composition_summary(composition) +
      [polygon_points(dependency) != polygon_points(composition)]
  end

  def dependency_summary(doc, polygon)
    points = polygon_points(polygon)
    rect = node_rect(doc, "A")
    [points.length, polygon.attributes["fill"], no_three_collinear?(points),
     rhombus?(points), points.none? { |point| inside_rect?(point, rect) }]
  end

  def composition_summary(polygon)
    points = polygon_points(polygon)
    [points.length, polygon.attributes["fill"], rhombus?(points)]
  end

  def filled_diamond_summary
    _doc, line, polygons = relationship_parts("A *--* B")
    [polygons.length, polygons.map { |polygon| polygon.attributes["fill"] },
     polygons.map { |polygon| polygon_points(polygon).length },
     polygons.map do |polygon|
       nearer_endpoint(polygon_points(polygon), line)
     end.sort]
  end

  def hollow_diamond_summary
    _doc, line, polygons = relationship_parts("A o.. B")
    polygon = polygons.first
    [line.attributes["stroke-dasharray"], polygons.length,
     polygon.attributes["fill"], nearer_endpoint(polygon_points(polygon), line)]
  end

  def two_way_marker_summary(source, edge_id)
    doc = rendered_document(source)
    group = relationship_group(doc, edge_id)
    [group.nil?, REXML::XPath.match(group, "polygon").empty?]
  end

  def two_way_marker_summaries
    [
      ["Animal <|--|> Zebra", "Animal_to_Zebra"],
      ["Animal o--< Zebra", "Animal_to_Zebra"],
      ["Animal *..|> Zebra", "Animal_to_Zebra"],
    ].map { |source, edge_id| two_way_marker_summary(source, edge_id) }
  end
end

RSpec.describe Sirena::Renderer::ClassDiagram do
  let(:renderer) { described_class.new }

  describe "#render" do
    let(:graph) do
      {
        id: "class_diagram",
        children: [
          {
            id: "Animal",
            x: 10,
            y: 10,
            width: 150,
            height: 100,
            labels: [{ text: "Animal", width: 60, height: 16 }],
            metadata: {
              name: "Animal",
              stereotype: nil,
              attributes: [
                { name: "age", type: "int", visibility: "protected",
                  text: "#age: int" },
              ],
              methods: [
                { name: "breathe", parameters: nil, return_type: nil,
                  visibility: "public", text: "+breathe" },
              ],
            },
          },
          {
            id: "Dog",
            x: 200,
            y: 10,
            width: 150,
            height: 80,
            labels: [{ text: "Dog", width: 40, height: 16 }],
            metadata: {
              name: "Dog",
              stereotype: nil,
              attributes: [],
              methods: [
                { name: "bark", parameters: nil, return_type: nil,
                  visibility: "public", text: "+bark" },
              ],
            },
          },
        ],
        edges: [
          {
            id: "Dog_to_Animal",
            sources: ["Dog"],
            targets: ["Animal"],
            metadata: { relationship_type: "inheritance" },
          },
        ],
      }
    end
    let(:scene) { Sirena::Layout::ClassDiagram.from_graph(graph) }
    let(:empty_scene) do
      Sirena::Layout::ClassDiagram.from_graph(
        { id: "class_diagram", children: [], edges: [] },
      )
    end

    it "renders graph to SVG document" do
      svg = renderer.render(scene)

      expect([svg.class, svg.width.positive?, svg.height.positive?])
        .to eq([Sirena::Svg::Document, true, true])
    end

    it "serializes routed Scene bends without recalculating them" do
      expect(ClassDiagramSpecHelpers.rendered_bent_route(renderer, scene))
        .to eq("M 100 25 L 150 80 L 200 25")
    end

    it "routes typed Scenes through the released collection hooks" do
      calls = []
      ClassDiagramSpecHelpers.record_collection_hooks(renderer, calls)
      renderer.render(scene)

      expect(calls).to eq(%i[render_relationships render_classes])
    end

    it "includes class boxes in SVG" do
      svg = renderer.render(scene)

      groups = svg.children.grep(Sirena::Svg::Group)
      expect(groups.length).to be > 0
    end

    it "renders class boxes as rectangles" do
      svg = renderer.render(scene)

      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
    end

    it "renders class names as text elements" do
      texts = ClassDiagramSpecHelpers.svg_texts(renderer.render(scene))
      expect([texts.empty?, texts.include?("Animal")]).to eq([false, true])
    end

    it "renders attributes with visibility symbols" do
      texts = ClassDiagramSpecHelpers.svg_texts(renderer.render(scene))
        .grep(/age/)
      expect([texts.empty?, texts.first.include?("#")]).to eq([false, true])
    end

    it "renders methods with visibility symbols" do
      texts = ClassDiagramSpecHelpers.svg_texts(renderer.render(scene))
        .grep(/breathe|bark/)
      expect([texts.empty?, texts.first.include?("+")]).to eq([false, true])
    end

    it "renders compartment separators" do
      svg = renderer.render(scene)

      groups = svg.children.grep(Sirena::Svg::Group)

      lines = groups.flat_map(&:children).grep(Sirena::Svg::Line)

      expect(lines).not_to be_empty
    end

    it "renders relationships" do
      svg = renderer.render(scene)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?("rel-")
      end

      expect(groups).not_to be_empty
    end

    it "renders stereotypes when present" do
      graph[:children][0][:metadata][:stereotype] = "interface"
      texts = ClassDiagramSpecHelpers.svg_texts(renderer.render(scene))
        .grep(/«.*»/)
      expect([texts.empty?, texts.first.include?("interface")])
        .to eq([false, true])
    end

    it "keeps unchanged default output byte-equivalent to the legacy graph" do
      expect(renderer.render(scene).to_xml).to eq(renderer.render(graph).to_xml)
    end

    it "renders the empty Scene at the legacy canvas size without elements" do
      svg = renderer.render(empty_scene)

      expect([svg.width, svg.height, svg.view_box, svg.children.map(&:id)])
        .to eq([880.0, 680.0, "0 0 880 680", ["defs"]])
    end
  end

  describe "theme font sizes" do
    let(:source) do
      "class A <<interface>>\nA \"1\" -- \"many\" B : owns"
    end
    let(:high_contrast_document) do
      ClassDiagramSpecHelpers.rendered_document(
        source, theme: :high_contrast
      )
    end

    it "migrates stereotypes, labels, and cardinalities to default small" do
      document = ClassDiagramSpecHelpers.rendered_document(source)
      sizes = ClassDiagramSpecHelpers.font_sizes(
        document, %w[«interface» owns 1 many]
      )

      expect(sizes).to all(eq("12"))
    end

    it "emits high-contrast large and small sizes from its own Scene" do
      expect(ClassDiagramSpecHelpers.theme_font_sizes(high_contrast_document))
        .to eq(["18", %w[14 14 14 14]])
    end
  end

  describe "released protected hooks" do
    let(:released_hooks) do
      {
        calculate_width: 1, calculate_height: 1, add_markers: 1,
        add_inheritance_marker: 1, add_composition_marker: 1,
        add_aggregation_marker: 1, render_classes: 2, render_class: 2,
        render_class_content: 3, render_stereotype: 5,
        render_class_name: 5, render_attributes: 5, render_methods: 5,
        visibility_symbol: 1, render_relationships: 2,
        render_relationship: 3, find_node: 2,
        calculate_connection_point: 2, render_relationship_line: 4,
        render_relationship_marker: 4, render_triangle_marker: 4,
        render_diamond_marker: 4, render_relationship_labels: 4
      }
    end

    it "preserves their names and arities" do
      arities = ClassDiagramSpecHelpers.method_arities(
        renderer, released_hooks.keys
      )

      expect(arities).to eq(released_hooks)
    end

    it "keeps them protected" do
      expect(released_hooks.keys).to all(
        satisfy { |name| described_class.protected_method_defined?(name) },
      )
    end

    it "delegates legacy connection geometry to Layout" do
      from = { x: 0, y: 0, width: 100, height: 50 }
      to = { x: 200, y: 0, width: 100, height: 50 }

      expect(renderer.send(:calculate_connection_point, from, to))
        .to eq(Sirena::Layout::ClassDiagram.connection_point(from, to))
    end
  end

  # These specs assert against a full Sirena::Engine#render of real
  # mermaid source, not a hand-built graph fixture and never a direct call
  # to a private marker method -- the shape two earlier Codex rounds
  # verified with hand-picked coordinates, which is exactly what hid the
  # next defect (Codex High, class_diagram.rb:482): the dependency dart's
  # coordinates from a direct render_dart_marker call bore no relation to
  # what the real render path actually drew.
  describe "#render mixed-marker relationships, from real mermaid source" do
    it "renders an aggregation-start/inheritance-end marker pair " \
       "on a solid line (o--|>)" do
      expect(ClassDiagramSpecHelpers.aggregation_inheritance_summary)
        .to eq([nil, "#ffffff", :start, "#ffffff", :end])
    end

    it "renders a dependency-start/composition-end marker pair " \
       "on a solid line (<--*)" do
      expect(ClassDiagramSpecHelpers.dependency_composition_summary).to eq(
        [4, "#000000", true, false, true, 4, "#000000", true, true],
      )
    end

    it "renders a filled diamond at both ends (*--*)" do
      expect(ClassDiagramSpecHelpers.filled_diamond_summary)
        .to eq([2, %w[#000000 #000000], [4, 4], %i[end start]])
    end

    it "renders a hollow diamond on a dashed line, no end marker (o..)" do
      expect(ClassDiagramSpecHelpers.hollow_diamond_summary)
        .to eq(["5,5", 1, "#ffffff", :start])
    end

    # H2: mermaid defines two-way relations structurally as
    # [Relation Type][Link][Relation Type], not a fixed list of strings
    # (https://mermaid.js.org/syntax/classDiagram#two-way-relations).
    # mermaid's own documented example, plus two combinations the old
    # 4-entry hardcoded table never had.
    it "renders every two-way marker combination, parsed structurally" do
      expect(ClassDiagramSpecHelpers.two_way_marker_summaries)
        .to eq([[false, false]] * 3)
    end
  end
end
