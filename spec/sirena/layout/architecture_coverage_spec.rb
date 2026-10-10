# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture do
  subject(:layout) { described_class.new }

  include LayoutIrShorthand

  def service(id, label: id, group_id: nil)
    Sirena::Diagram::Architecture::Service.new(
      id: id, label: label, group_id: group_id,
    )
  end

  def junction(id)
    Sirena::Diagram::Architecture::Junction.new(id: id)
  end

  def group(id, parent_id: nil)
    Sirena::Diagram::Architecture::Group.new(id: id, parent_id: parent_id)
  end

  def edge(source, target)
    Sirena::Diagram::Architecture::Edge.new(
      from_id: source, to_id: target, from_position: "R", to_position: "L",
    )
  end

  def diagram(services: [], junctions: [], groups: [], edges: [])
    Sirena::Diagram::Architecture.new(
      services: services, junctions: junctions, groups: groups, edges: edges,
    )
  end

  def routed_scene
    layout.call(
      diagram(
        services: [service("source"), service("target")],
        junctions: [junction("obstacle")],
        edges: [edge("source", "target")],
      ),
    )
  end

  def missing_endpoint_graph
    ir_graph(
      id: "architecture",
      nodes: [ir_node(id: "source", label: "Source", role: "service")],
      edges: [ir_edge(id: "missing", source_id: "source",
                      target_id: "absent")],
    )
  end

  def cyclic_group_graph
    layout.build_graph(
      diagram(
        services: [service("api", group_id: "one")],
        groups: [group("one", parent_id: "two"),
                 group("two", parent_id: "one")],
      ),
    )
  end

  it "lays out a graph without a settings node" do
    scene = layout.call(ir_graph(id: "architecture", nodes: []))

    expect(scene).to have_attributes(
      children: [], edges: [], width: 40, height: 40,
    )
  end

  it "omits the label for an unlabeled service" do
    scene = layout.call(diagram(services: [service("api", label: nil)]))

    expect(scene.children.first.labels).to be_empty
  end

  it "routes past a junction that is not an endpoint" do
    expect(routed_scene.edges.first.sections).not_to be_empty
  end

  it "omits an edge whose endpoint is absent" do
    expect(layout.build_graph(missing_endpoint_graph)[:edges]).to be_empty
  end

  it "bounds cyclic ancestry during direct graph construction" do
    expect([cyclic_group_graph[:width], cyclic_group_graph[:height]])
      .to all(be_finite)
  end

  it "uses default typography when the injected theme has none" do
    scene = layout.call(
      diagram(services: [service("api")]), theme: Sirena::Theme.new
    )

    expect(scene.children.first.width)
      .to be >= described_class::DEFAULT_SERVICE_WIDTH
  end
end
