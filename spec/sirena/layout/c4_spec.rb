# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/c4"

RSpec.describe Sirena::Layout::C4 do
  subject(:layout) { described_class.new }

  def flatten(nodes)
    nodes.flat_map { |node| [node, *flatten(node.children)] }
  end

  def diagram(level: "Context", elements: [], relationships: [], boundaries: [])
    Sirena::Diagram::C4.new(
      level: level, elements: elements, relationships: relationships,
      boundaries: boundaries
    )
  end

  def engine_scenes(path)
    source = File.read(path)
    engine = Sirena::Engine.new
    [engine.render(source, layout_engine: :elk), engine.render(source)]
  end

  def expect_right_error(level)
    graph = layout.build_graph(diagram(level: level, elements: [element("a")]))
    expect { layout.send(:placer).apply(graph) }
      .to raise_error(Sirena::Layout::LayoutError, /direction RIGHT/)
  end

  def element(id, type: "System", boundary_id: nil)
    Sirena::Diagram::C4Element.new(
      id: id, label: id.upcase, element_type: type,
      boundary_id: boundary_id
    )
  end

  def boundary_endpoint_diagram
    boundary = Sirena::Diagram::C4Boundary.new(
      id: "scope", label: "Scope", boundary_type: "System_Boundary",
    )
    relationship = Sirena::Diagram::C4Relationship.new(
      from_id: "scope", to_id: "a", label: "bad",
    )
    diagram(elements: [element("a")], relationships: [relationship],
            boundaries: [boundary])
  end

  let(:context_scene) do
    source = File.read("examples/c4/01-context-diagram.mmd")
    layout.call(Sirena::Parser::C4.new.parse(source))
  end
  let(:context_nodes) { context_scene.children.to_h { |node| [node.id, node] } }
  let(:container_scene) do
    source = File.read("examples/c4/02-container-diagram.mmd")
    layout.call(Sirena::Parser::C4.new.parse(source))
  end
  let(:container_nodes) { flatten(container_scene.children) }
  let(:nested_diagram) { build_nested_diagram }

  def build_nested_diagram
    outer, inner = nested_boundaries
    user, api = nested_elements(outer, inner)
    relation = nested_relationship(user, api)
    Sirena::Diagram::C4.new(
      id: "landscape", title: "Ordering", level: "Container",
      layout_config: "shapeInRow=2", boundaries: [outer, inner],
      elements: [user, api], relationships: [relation]
    )
  end

  def nested_boundaries
    outer = Sirena::Diagram::C4Boundary.new(
      id: "company", label: "Company", boundary_type: "Enterprise_Boundary",
      link: "https://example.test/company", tags: "owned"
    )
    inner = Sirena::Diagram::C4Boundary.new(
      id: "platform", label: "Platform", boundary_type: "System_Boundary",
      parent_id: outer.id
    )
    [outer, inner]
  end

  def nested_elements(outer, inner)
    user = Sirena::Diagram::C4Element.new(
      id: "user", label: "User", element_type: "Person_Ext",
      description: "Places orders", boundary_id: outer.id, external: true
    )
    api = Sirena::Diagram::C4Element.new(
      id: "api", label: "API", element_type: "Container",
      description: "Accepts orders", technology: "Ruby",
      boundary_id: inner.id
    )
    [user, api]
  end

  def nested_relationship(user, api)
    Sirena::Diagram::C4Relationship.new(
      from_id: user.id, to_id: api.id, label: "Places order",
      technology: "HTTPS", rel_type: "BiRel"
    )
  end

  it "returns a typed Scene" do
    expect(context_scene).to be_a(described_class::Scene)
  end

  it "stores a person's final default dimensions" do
    expect(context_nodes["user"]).to have_attributes(
      kind: "person", width: described_class::PERSON_WIDTH.to_f,
      height: described_class::PERSON_HEIGHT.to_f
    )
  end

  it "stores a system's final default dimensions" do
    expect(context_nodes["webapp"]).to have_attributes(
      kind: "system", width: described_class::SYSTEM_WIDTH.to_f,
      height: described_class::SYSTEM_HEIGHT.to_f
    )
  end

  it "sizes the final canvas from recursively nested children plus padding" do
    width = container_nodes.map { |node| node.x + node.width }.max
    height = container_nodes.map { |node| node.y + node.height }.max
    padding = described_class::DIAGRAM_PADDING
    expect([container_scene.width, container_scene.height])
      .to eq([width, height].map { |size| size + padding })
  end

  it "keeps nested boundary children" do
    boundary = container_scene.children.find { |node| node.id == "ecommerce" }
    expect(boundary.children).not_to be_empty
  end

  it "keeps Grid as the default placement" do
    allow(Sirena::Layout::Grid).to receive(:apply).and_call_original
    layout.call(diagram)
    expect(Sirena::Layout::Grid).to have_received(:apply).once
  end

  it "lets Engine select ELK for Context and Container DOWN layouts" do
    paths = %w[01-context-diagram.mmd 02-container-diagram.mmd]
    scenes = paths.map { |path| engine_scenes("examples/c4/#{path}") }
    expect(scenes).to all(satisfy { |elk, grid| elk != grid })
  end

  it "retains explicit RIGHT errors for Component and Code" do
    layout.placement = :elk
    %w[Component Code].each { |level| expect_right_error(level) }
  end

  it "lays out direct graph IR byte-identically to the private diagram" do
    private_scene = layout.call(nested_diagram)
    shared_scene = layout.call(c4_graph)

    expect(Marshal.dump(shared_scene)).to eq(Marshal.dump(private_scene))
  end

  it "retains nested elements and relationship labels through IR" do
    expect(nested_scene_evidence).to eq(expected_nested_scene_evidence)
  end

  it "normalizes an unclassified valid element to a system node" do
    scene = layout.call(diagram(elements: [element("x", type: "Unknown")]))

    expect(scene.children.first).to have_attributes(
      id: "x", kind: "system", width: described_class::SYSTEM_WIDTH.to_f,
      height: described_class::SYSTEM_HEIGHT.to_f
    )
  end

  it "refuses a relationship with a missing endpoint" do
    relation = Sirena::Diagram::C4Relationship.new(from_id: nil, to_id: "b")
    invalid = diagram(elements: [element("b")], relationships: [relation])
    expect { layout.call(invalid) }
      .to raise_error(Sirena::Layout::LayoutError)
  end

  it "refuses a relationship with an unknown endpoint" do
    expect { layout.call(unknown_endpoint_diagram) }
      .to raise_error(Sirena::Layout::LayoutError)
  end

  it "does not accept a boundary as a relationship endpoint" do
    expect { layout.call(boundary_endpoint_diagram) }
      .to raise_error(Sirena::Layout::LayoutError)
  end

  def unknown_endpoint_diagram
    relation = Sirena::Diagram::C4Relationship.new(
      from_id: "a", to_id: "missing",
    )
    diagram(elements: [element("a")], relationships: [relation])
  end

  def c4_graph
    Sirena::Notation::Mermaid::IRAdapters::C4.call(nested_diagram)
  end

  def nested_scene_evidence
    scene = layout.call(c4_graph)
    edge = scene.edges.fetch(0)
    [scene_node_signature(scene), *scene_edge_signature(edge)]
  end

  def scene_node_signature(scene)
    flatten(scene.children).map { |node| [node.id, node.kind] }
  end

  def scene_edge_signature(edge)
    [edge.source, edge.target, edge.labels.map(&:text), edge.arrowheads.length]
  end

  def expected_nested_scene_evidence
    nodes = [["company", "boundary"], ["platform", "boundary"],
             ["api", "container"], ["user", "person"]]
    [nodes, "user", "api", ["Places order", "[HTTPS]"], 2]
  end
end
