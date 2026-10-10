# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::C4 do
  subject(:renderer) { described_class.new }

  def label(text, x_coord: 60, y_coord: 40, size: 14)
    Sirena::Layout::C4::Label.new(
      text: text, x: x_coord, y: y_coord, font_size: size,
    )
  end

  def node(id, kind, **attributes)
    x_coord = attributes.delete(:x_coord) || 10
    external = attributes.delete(:external) || false
    labels = attributes.delete(:labels) || [label(id)]
    Sirena::Layout::C4::Node.new(
      id: id, kind: kind, x: x_coord, y: 20, width: 100, height: 60,
      external: external, labels: labels, **attributes
    )
  end

  def scene(children: [], edges: [], width: 800, height: 600)
    Sirena::Layout::C4::Scene.new(
      width: width, height: height, view_box: "0 0 #{width} #{height}",
      children: children, edges: edges
    )
  end

  it "uses typed empty-scene dimensions verbatim" do
    svg = renderer.render(scene)
    expect([svg.width, svg.height, svg.to_xml.include?("<g")])
      .to eq([800, 600, false])
  end

  it "uses every element palette including external variants" do
    expect(palette_fills).to eq(expected_palette_fills)
  end

  it "uses typed label font sizes in source order" do
    xml = renderer.render(scene(children: [sized_label_node])).to_xml
    expect(xml.scan(/font-size="(\d+)\.0"/).flatten).to eq(%w[14 11 10 10])
  end

  it "skips unpositioned elements and boundaries but keeps nested content" do
    xml = renderer.render(scene(children: unpositioned_nodes)).to_xml
    evidence = [xml.include?("element-missing"), xml.include?("boundary-b"),
                xml.include?("element-inner")]
    expect(evidence).to eq([false, false, true])
  end

  it "renders nested positioned boundaries before their child elements" do
    child = node("inner", "container")
    boundary = node("b", "boundary", labels: [label("Boundary")],
                                     children: [child])
    xml = renderer.render(scene(children: [boundary])).to_xml
    expect(xml).to include("boundary-b", "Boundary", "element-inner")
  end

  it "renders a positioned boundary even when it has no label" do
    boundary = node("u", "boundary", labels: [], children: [])

    expect(renderer.render(scene(children: [boundary])).to_xml)
      .to include("boundary-u")
  end

  it "points an arrowhead left when the typed target is left of its source" do
    xml = renderer.render(scene(edges: [left_arrow_edge])).to_xml
    expect(xml).to include('points="50,50 58,46 58,54"')
  end

  it "refuses relationships whose endpoints do not resolve" do
    expect { Sirena::Layout::C4.new.call(unresolved_diagram) }
      .to raise_error(Sirena::Layout::LayoutError)
  end

  def palette_nodes
    point = Sirena::Layout::C4::Point
    person = node("p", "person", external: true,
                                 head_center: point.new(x: 60, y: 40),
                                 body_center: point.new(x: 60, y: 75))
    [person, node("s", "system", external: true),
     node("c", "container"), node("k", "component")]
  end

  def palette_fills
    groups = renderer.render(scene(children: palette_nodes)).children
      .grep(Sirena::Svg::Group)
    groups.to_h do |group|
      [group.id, group.children.grep(Sirena::Svg::Rect).first.fill]
    end
  end

  def expected_palette_fills
    colors = Sirena::Theme::Registry.get(:default).colors
    {
      "element-p" => colors.secondary,
      "element-s" => colors.secondary,
      "element-c" => colors.primary,
      "element-k" => colors.surface_variant,
    }
  end

  def sized_label_node
    labels = [14, 11, 10, 10].map.with_index do |size, index|
      label(index.to_s, size: size)
    end
    node("s", "system", labels: labels)
  end

  def unpositioned_nodes
    missing = Sirena::Layout::C4::Node.new(id: "missing", kind: "system")
    boundary = Sirena::Layout::C4::Node.new(
      id: "b", kind: "boundary", children: [node("inner", "container")],
      labels: []
    )
    [missing, boundary]
  end

  def left_arrow_edge
    point = Sirena::Layout::C4::Point
    section = Sirena::Layout::C4::Section.new(
      start_point: point.new(x: 450, y: 50),
      end_point: point.new(x: 50, y: 50),
    )
    Sirena::Layout::C4::Edge.new(
      id: "e", source: "b", target: "a", sections: [section],
      line_end: point.new(x: 42, y: 50),
      arrowheads: ["50,50 58,46 58,54"]
    )
  end

  def unresolved_diagram
    source = <<~MERMAID
      C4Context
        System(a, "A")
        Rel(a, missing, "bad")
    MERMAID
    Sirena::Parser::C4.new.parse(source)
  end
end
