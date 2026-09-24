# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'

# Pure geometry/XML helpers, single-user (this file only): module_function
# so they can be called at describe-body level to generate examples.
module ClassDiagramSpecHelpers
  module_function

  def rendered_document(source)
    svg = Sirena::Engine.new.render("classDiagram\n  #{source}\n")
    REXML::Document.new(svg)
  end

  def relationship_group(doc, edge_id)
    REXML::XPath.first(doc, "//*[@id='rel-#{edge_id}']")
  end

  def node_rect(doc, node_id)
    REXML::XPath.first(doc, "//*[@id='class-#{node_id}']/rect")
  end

  def polygon_points(element)
    element.attributes['points'].split(' ').map { |pt| pt.split(',').map(&:to_f) }
  end

  def rect_bounds(rect)
    x = rect.attributes['x'].to_f
    y = rect.attributes['y'].to_f
    [x, x + rect.attributes['width'].to_f, y, y + rect.attributes['height'].to_f]
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
    centroid = [points.sum { |p| p[0] } / points.length, points.sum { |p| p[1] } / points.length]
    start_pt = [line.attributes['x1'].to_f, line.attributes['y1'].to_f]
    end_pt = [line.attributes['x2'].to_f, line.attributes['y2'].to_f]
    dist_start = Math.hypot(centroid[0] - start_pt[0], centroid[1] - start_pt[1])
    dist_end = Math.hypot(centroid[0] - end_pt[0], centroid[1] - end_pt[1])
    dist_start < dist_end ? :start : :end
  end

  # Composition/aggregation's diamond is a rhombus: all four edges equal
  # length. The dependency dart is deliberately asymmetric (see
  # DART_NEAR/DART_FAR/DART_WIDTH in the renderer) so it reads as a
  # distinct glyph even though both are 4-point filled polygons.
  def rhombus?(points)
    return false unless points.length == 4

    edges = points.each_cons(2).to_a.push([points.last, points.first])
      .map { |(x1, y1), (x2, y2)| Math.hypot(x2 - x1, y2 - y1) }
    edges.map { |e| e.round(2) }.uniq.length == 1
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
end

RSpec.describe Sirena::Renderer::ClassDiagram do
  let(:renderer) { described_class.new }

  describe '#render' do
    let(:graph) do
      {
        id: 'class_diagram',
        children: [
          {
            id: 'Animal',
            x: 10,
            y: 10,
            width: 150,
            height: 100,
            labels: [{ text: 'Animal', width: 60, height: 16 }],
            metadata: {
              name: 'Animal',
              stereotype: nil,
              attributes: [
                { name: 'age', type: 'int', visibility: 'protected' }
              ],
              methods: [
                { name: 'breathe', parameters: nil, return_type: nil,
                  visibility: 'public' }
              ]
            }
          },
          {
            id: 'Dog',
            x: 200,
            y: 10,
            width: 150,
            height: 80,
            labels: [{ text: 'Dog', width: 40, height: 16 }],
            metadata: {
              name: 'Dog',
              stereotype: nil,
              attributes: [],
              methods: [
                { name: 'bark', parameters: nil, return_type: nil,
                  visibility: 'public' }
              ]
            }
          }
        ],
        edges: [
          {
            id: 'Dog_to_Animal',
            sources: ['Dog'],
            targets: ['Animal'],
            metadata: { relationship_type: 'inheritance' }
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

    it 'includes class boxes in SVG' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)
      expect(groups.length).to be > 0
    end

    it 'renders class boxes as rectangles' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
    end

    it 'renders class names as text elements' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts).not_to be_empty
      # `content` is `collection: true`, so read it through Array(...).
      class_names = texts.map { |t| Array(t.content).join }
      expect(class_names).to include('Animal')
    end

    it 'renders attributes with visibility symbols' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      attr_texts = texts.map { |t| Array(t.content).join }.grep(/age/)
      expect(attr_texts).not_to be_empty
      expect(attr_texts.first).to include('#')
    end

    it 'renders methods with visibility symbols' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      method_texts = texts.map { |t| Array(t.content).join }.grep(/breathe|bark/)
      expect(method_texts).not_to be_empty
      expect(method_texts.first).to include('+')
    end

    it 'renders compartment separators' do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      lines = groups.flat_map(&:children).grep(Sirena::Svg::Line)

      expect(lines).not_to be_empty
    end

    it 'renders relationships' do
      svg = renderer.render(graph)

      groups = svg.children.select do |c|
        c.is_a?(Sirena::Svg::Group) && c.id&.start_with?('rel-')
      end

      expect(groups).not_to be_empty
    end

    it 'renders stereotypes when present' do
      graph[:children][0][:metadata][:stereotype] = 'interface'
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      stereotype_texts = texts.map { |t| Array(t.content).join }.grep(/<<.*>>/)
      expect(stereotype_texts).not_to be_empty
      expect(stereotype_texts.first).to include('interface')
    end
  end

  # These specs assert against a full Sirena::Engine#render of real
  # mermaid source, not a hand-built graph fixture and never a direct call
  # to a private marker method -- the shape two earlier Codex rounds
  # verified with hand-picked coordinates, which is exactly what hid the
  # next defect (Codex High, class_diagram.rb:482): the dependency dart's
  # coordinates from a direct render_dart_marker call bore no relation to
  # what the real render path actually drew.
  describe '#render mixed-marker relationships, from real mermaid source' do
    it 'renders an aggregation-start/inheritance-end marker pair on a solid line (o--|>)' do
      doc = ClassDiagramSpecHelpers.rendered_document('A o--|> B')
      group = ClassDiagramSpecHelpers.relationship_group(doc, 'A_to_B')
      line = REXML::XPath.first(group, 'line')
      expect(line.attributes['stroke-dasharray']).to be_nil

      polygons = REXML::XPath.match(group, 'polygon')
      diamond = polygons.find { |p| ClassDiagramSpecHelpers.polygon_points(p).length == 4 }
      triangle = polygons.find { |p| ClassDiagramSpecHelpers.polygon_points(p).length == 3 }
      expect(diamond.attributes['fill']).to eq('#ffffff')
      expect(ClassDiagramSpecHelpers.nearer_endpoint(ClassDiagramSpecHelpers.polygon_points(diamond), line)).to eq(:start)
      # mermaid's extension/inheritance marker is hollow, not filled.
      expect(triangle.attributes['fill']).to eq('#ffffff')
      expect(ClassDiagramSpecHelpers.nearer_endpoint(ClassDiagramSpecHelpers.polygon_points(triangle), line)).to eq(:end)
    end

    it 'renders a dependency-start/composition-end marker pair on a solid line (<--*)' do
      doc = ClassDiagramSpecHelpers.rendered_document('A <--* B')
      group = ClassDiagramSpecHelpers.relationship_group(doc, 'A_to_B')
      line = REXML::XPath.first(group, 'line')
      expect(line.attributes['stroke-dasharray']).to be_nil

      polygons = REXML::XPath.match(group, 'polygon')
      expect(polygons.length).to eq(2)
      dependency = polygons.find { |p| ClassDiagramSpecHelpers.nearer_endpoint(ClassDiagramSpecHelpers.polygon_points(p), line) == :start }
      composition = polygons.find { |p| ClassDiagramSpecHelpers.nearer_endpoint(ClassDiagramSpecHelpers.polygon_points(p), line) == :end }
      dep_points = ClassDiagramSpecHelpers.polygon_points(dependency)
      comp_points = ClassDiagramSpecHelpers.polygon_points(composition)

      expect(dep_points.length).to eq(4)
      expect(dependency.attributes['fill']).to eq('#000000')
      expect(ClassDiagramSpecHelpers.no_three_collinear?(dep_points)).to be(true)
      # Not the same filled shape as composition's diamond.
      expect(ClassDiagramSpecHelpers.rhombus?(dep_points)).to be(false)

      # Defects (b) and (c) -- wrong direction, and drawn inside the
      # source node so it is painted over -- are ONE defect on this
      # renderer: render_dart_marker builds the whole dart on the `to`
      # side of its own anchor point (DART_NEAR and DART_FAR both offset
      # the same direction), so a dart built on the wrong side is, by
      # construction, also the dart whose wide back edge lands inside
      # node A's box (Codex High, class_diagram.rb:482, coordinates
      # (153,50) (136,55) (144.5,50) (136,45) against A's real box
      # 0..150 -- reproduced against the real render, not a hand call).
      # One property catches both: every vertex of the dart must sit
      # strictly outside A's own rendered rectangle.
      a_rect = ClassDiagramSpecHelpers.node_rect(doc, 'A')
      expect(dep_points.none? { |pt| ClassDiagramSpecHelpers.inside_rect?(pt, a_rect) }).to be(true)

      expect(comp_points.length).to eq(4)
      expect(composition.attributes['fill']).to eq('#000000')
      expect(ClassDiagramSpecHelpers.rhombus?(comp_points)).to be(true)
      # The dependency dart is a distinct glyph from composition's diamond
      # at the identical connection points, not just "not a rhombus".
      expect(dep_points).not_to eq(comp_points)
    end

    it 'renders a filled diamond at both ends (*--*)' do
      doc = ClassDiagramSpecHelpers.rendered_document('A *--* B')
      group = ClassDiagramSpecHelpers.relationship_group(doc, 'A_to_B')
      polygons = REXML::XPath.match(group, 'polygon')
      line = REXML::XPath.first(group, 'line')

      expect(polygons.length).to eq(2)
      expect(polygons.map { |p| p.attributes['fill'] }).to all(eq('#000000'))
      expect(polygons.map { |p| ClassDiagramSpecHelpers.polygon_points(p).length }).to all(eq(4))
      expect(polygons.map { |p| ClassDiagramSpecHelpers.nearer_endpoint(ClassDiagramSpecHelpers.polygon_points(p), line) })
        .to contain_exactly(:start, :end)
    end

    it 'renders a hollow diamond on a dashed line, no end marker (o..)' do
      doc = ClassDiagramSpecHelpers.rendered_document('A o.. B')
      group = ClassDiagramSpecHelpers.relationship_group(doc, 'A_to_B')
      line = REXML::XPath.first(group, 'line')
      expect(line.attributes['stroke-dasharray']).to eq('5,5')

      polygons = REXML::XPath.match(group, 'polygon')
      expect(polygons.length).to eq(1)
      expect(polygons.first.attributes['fill']).to eq('#ffffff')
      expect(ClassDiagramSpecHelpers.nearer_endpoint(ClassDiagramSpecHelpers.polygon_points(polygons.first), line)).to eq(:start)
    end

    # H2: mermaid defines two-way relations structurally as
    # [Relation Type][Link][Relation Type], not a fixed list of strings
    # (https://mermaid.js.org/syntax/classDiagram#two-way-relations).
    # mermaid's own documented example, plus two combinations the old
    # 4-entry hardcoded table never had.
    it 'renders every two-way marker combination, parsed structurally' do
      [
        ['Animal <|--|> Zebra', 'Animal_to_Zebra'],
        ['Animal o--< Zebra', 'Animal_to_Zebra'],
        ['Animal *..|> Zebra', 'Animal_to_Zebra']
      ].each do |source, edge_id|
        doc = ClassDiagramSpecHelpers.rendered_document(source)
        group = ClassDiagramSpecHelpers.relationship_group(doc, edge_id)
        expect(group).not_to be_nil
        expect(REXML::XPath.match(group, 'polygon')).not_to be_empty
      end
    end
  end
end
