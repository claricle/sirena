# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::C4 do
  subject(:renderer) { described_class.new }

  def scene_for(path)
    source = File.read(path)
    diagram = Sirena::Parser::C4.new.parse(source)
    Sirena::Layout::C4.new.call(diagram)
  end

  let(:context_scene) { scene_for("examples/c4/01-context-diagram.mmd") }
  let(:context_xml) { renderer.render(context_scene).to_xml }

  it "renders a typed Scene using its final canvas" do
    svg = renderer.render(context_scene)
    expect(context_scene).to be_a(Sirena::Layout::C4::Scene)
    expect(context_scene.children).to all(be_a(Sirena::Layout::C4::Node))
    expect([svg.width, svg.height, svg.view_box])
      .to eq([context_scene.width, context_scene.height,
              context_scene.view_box])
  end

  it "renders people, systems, external palettes, labels, and relationships" do
    colors = Sirena::Theme::Registry.get(:default).colors
    expect(context_xml).to include('id="element-user"', "User",
                                   "A system user", colors.primary)
    expect(context_xml).to include('id="element-webapp"', "Main application",
                                   colors.primary)
    expect(context_xml).to include('id="element-email"', "Sends notifications",
                                   colors.secondary)
    expect(context_xml).to include('id="rel_0"', "Uses", "<polygon")
  end

  it "renders the person head and body from typed points" do
    person = context_scene.children.find { |node| node.kind == "person" }
    expect(person.head_center).to be_a(Sirena::Layout::C4::Point)
    expect(context_xml).to include("<circle", "<ellipse")
  end

  it "renders nested boundaries and their child containers" do
    scene = scene_for("examples/c4/02-container-diagram.mmd")
    xml = renderer.render(scene).to_xml
    boundary = scene.children.find { |node| node.kind == "boundary" }
    primary = Sirena::Theme::Registry.get(:default).colors.primary
    expect(boundary.children).not_to be_empty
    expect(xml).to include('id="boundary-ecommerce"', "E-commerce System")
    expect(xml).to include('id="element-webapp"', primary)
    expect(xml).to include('stroke-dasharray="10,5"')
  end

  it "renders bidirectional relationships with two arrowheads " \
     "and both labels" do
    source = <<~MERMAID
      C4Context
        System(a, "A")
        System(b, "B")
        BiRel(a, b, "Syncs", "HTTPS")
    MERMAID
    diagram = Sirena::Parser::C4.new.parse(source)
    scene = Sirena::Layout::C4.new.call(diagram)
    edge = scene.edges.first
    xml = renderer.render(scene).to_xml
    expect(edge.arrowheads.length).to eq(2)
    expect(xml.scan("<polygon").size).to eq(2)
    expect(xml).to include("Syncs", "[HTTPS]")
    expect(xml).to include('font-size="12.0">Syncs<',
                           'font-size="10.0">[HTTPS]<')
  end

  it "uses semantic colors from the active theme" do
    dark = Sirena::Theme::Registry.get(:dark)
    themed = described_class.new(theme: dark).render(context_scene)

    expect(themed.to_xml).to include(
      dark.colors.primary, dark.colors.edge_stroke, dark.colors.background
    )
  end
end
