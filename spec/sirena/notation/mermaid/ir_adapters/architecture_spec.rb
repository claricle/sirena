# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/architecture"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Architecture do
  def outer_group
    Sirena::Diagram::Architecture::Group.new(
      id: "architecture", label: "Platform", icon: "cloud",
    )
  end

  def inner_group
    Sirena::Diagram::Architecture::Group.new(
      id: "nested", label: "Runtime", icon: "server",
      parent_id: outer_group.id
    )
  end

  def api_service
    Sirena::Diagram::Architecture::Service.new(
      id: "api", label: "Public API", icon: "internet",
      group_id: inner_group.id
    )
  end

  def worker_service
    Sirena::Diagram::Architecture::Service.new(
      id: "connection_0", label: "Worker", icon: "server",
      group_id: outer_group.id
    )
  end

  def routing_junction
    Sirena::Diagram::Architecture::Junction.new(
      id: "junction", group_id: inner_group.id,
    )
  end

  def diagram
    Sirena::Diagram::Architecture.new(
      id: "architecture", title: "Order platform", direction: "LR",
      theme: "forest", acc_title: "Order architecture",
      acc_descr: "Services and their routes",
      groups: [outer_group, inner_group],
      services: [api_service, worker_service],
      junctions: [routing_junction], edges: connections
    )
  end

  def connections
    [
      architecture_edge("api", "junction", "B", "T", "dispatch"),
      architecture_edge("junction", "connection_0", "R", "L", nil),
    ]
  end
  let(:ir) { described_class.call(diagram) }

  it "produces valid collision-safe graph IR without layout geometry" do
    expect(graph_evidence).to eq([true, "architecture_2", true, true])
  end

  it "preserves ordered groups, services, junctions, and containment" do
    expect(entity_signature).to eq(expected_entity_signature)
  end

  it "preserves labels, entity types, icons, and source identity" do
    expect(entity_content).to eq(expected_entity_content)
  end

  it "normalizes ordered resolvable edges, direction, and face intent" do
    expect(connection_signature).to eq(expected_connection_signature)
  end

  it "preserves title, accessibility, and diagram layout intent" do
    expect(settings_signature).to eq(expected_settings_signature)
  end

  def architecture_edge(source, target, from, to, label)
    Sirena::Diagram::Architecture::Edge.new(
      from_id: source, to_id: target, from_position: from,
      to_position: to, label: label
    )
  end

  def graph_evidence
    [ir.valid?, ir.id, collision_free?, geometry_free?]
  end

  def collision_free?
    identifiers = [ir.id, *ir.items.map(&:id)]
    identifiers.uniq.length == identifiers.length
  end

  def geometry_free?
    geometry = %i[x y width height sections bend_points]
    ir.items.all? do |item|
      geometry.none? { |name| item.respond_to?(name) }
    end
  end

  def entity_signature
    entity_nodes.map do |node|
      [node.id, node.role, node.parent_id]
    end
  end

  def expected_entity_signature
    [
      ["architecture", "group", nil],
      ["nested", "group", "architecture"],
      ["api", "service", "nested"],
      ["connection_0", "service", "architecture"],
      ["junction", "junction", "nested"],
    ]
  end

  def entity_content
    entity_nodes.map do |node|
      [node.label, fields_for(node.id)]
    end
  end

  def expected_entity_content
    [
      ["Platform", { "original_identifier" => "architecture",
                     "icon" => "cloud" }],
      ["Runtime", { "original_identifier" => "nested",
                    "icon" => "server",
                    "parent_identifier" => "architecture" }],
      ["Public API", { "original_identifier" => "api",
                       "group_identifier" => "nested",
                       "icon" => "internet" }],
      ["Worker", { "original_identifier" => "connection_0",
                   "group_identifier" => "architecture",
                   "icon" => "server" }],
      [nil, { "original_identifier" => "junction",
              "group_identifier" => "nested" }],
    ]
  end

  def connection_signature
    ir.edges.map do |edge|
      fields = fields_for(edge.parent_id)
      [edge.id, edge.source_id, edge.target_id, edge.role, edge.label,
       edge.properties.target_marker, fields]
    end
  end

  def expected_connection_signature
    [
      ["connection_0_2", "api", "junction", "directed_connection",
       "dispatch", "arrow",
       { "source_position" => "B", "target_position" => "T" }],
      ["connection_1", "junction", "connection_0",
       "directed_connection", nil, "arrow",
       { "source_position" => "R", "target_position" => "L" }],
    ]
  end

  def settings_signature
    settings = ir.nodes.find { |node| node.role == "diagram_settings" }
    [ir.label, ir.accessibility_title, ir.accessibility_description,
     fields_for(settings.id)]
  end

  def expected_settings_signature
    ["Order platform", "Order architecture", "Services and their routes",
     { "diagram_identifier" => "architecture", "layout_direction" => "LR",
       "theme" => "forest" }]
  end

  def entity_nodes
    ir.nodes.select { |node| entity_role?(node.role) }
  end

  def entity_role?(role)
    case role
    when "group", "service", "junction" then true
    else false
    end
  end

  def fields_for(parent_id)
    ir.nodes.select { |node| node.parent_id == parent_id }
      .select { |node| semantic_roles.include?(node.role) }
      .to_h { |node| [node.role, node.label] }
  end

  def semantic_roles
    %w[
      original_identifier icon parent_identifier group_identifier
      source_position target_position diagram_identifier layout_direction theme
    ]
  end
end
