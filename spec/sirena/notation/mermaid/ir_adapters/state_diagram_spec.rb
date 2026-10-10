# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/state_diagram"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::StateDiagram do
  def semantic_values(graph, parent_id, role)
    graph.nodes.filter_map do |node|
      node.label if node.parent_id == parent_id && node.role == role
    end
  end

  def state_node(graph, source_id)
    graph.nodes.find do |node|
      semantic_values(graph, node.id, "original_identifier") == [source_id]
    end
  end

  def parsed_diagram
    Sirena::Parser::StateDiagram.new.parse(<<~MERMAID).tap do |diagram|
      stateDiagram-v2
      direction LR
      state "Dormant" as Idle
      Idle : waiting
      state Decision <<choice>>
      Idle --> Decision : wake [ready]
      note right of Idle : current state
    MERMAID
      diagram.id = "machine"
      diagram.title = "Lifecycle"
      diagram.theme = "dark"
    end
  end

  def semantic_summary
    graph, unchanged = semantic_adaptation
    idle = state_node(graph, "Idle")
    {
      valid: graph.valid?, unchanged: unchanged,
      graph: [graph.id, graph.label, graph.role],
      idle: [idle.label, idle.role],
      display: semantic_values(graph, idle.id, "display_text"),
      transition: transition_summary(graph),
      details: transition_details(graph)
    }
  end

  def semantic_adaptation
    diagram = parsed_diagram
    before = Marshal.dump(diagram)
    graph = described_class.call(diagram)
    [graph, Marshal.dump(diagram) == before]
  end

  def transition_summary(graph)
    transition = graph.edges.first
    [transition.label, transition.role, transition.source_id,
     transition.target_id]
  end

  def transition_details(graph)
    transition = graph.edges.first
    [semantic_values(graph, transition.parent_id, "trigger"),
     semantic_values(graph, transition.parent_id, "guard_condition")]
  end

  def expected_semantic_summary
    {
      valid: true, unchanged: true,
      graph: %w[machine Lifecycle state_machine],
      idle: %w[Dormant state], display: %w[Dormant waiting],
      transition: ["wake [ready]", "state_transition", "Idle", "Decision"],
      details: [["wake"], ["ready"]]
    }
  end

  def containment_summary
    graph = described_class.call(containment_diagram)
    entities = %w[parent child sibling].map { |id| state_node(graph, id) }
    [entities.map(&:id), entities.map(&:parent_id),
     state_order(graph, entities)]
  end

  def containment_diagram
    child = Sirena::Diagram::StateNode.new(id: "child", label: "Child")
    parent = Sirena::Diagram::StateNode.new(
      id: "parent", label: "Parent", children: [child],
    )
    sibling = Sirena::Diagram::StateNode.new(id: "sibling", label: "Sibling")
    Sirena::Diagram::StateDiagram.new(states: [parent, sibling])
  end

  def state_order(graph, entities)
    entities.map do |node|
      semantic_values(graph, node.id, "sequence_index").first
    end
  end

  def collision_summary
    graph = described_class.call(collision_diagram)
    all_ids = [graph.id, *graph.nodes.map(&:id), *graph.edges.map(&:id)]
    edge = graph.edges.first
    [graph.valid?, all_ids.uniq == all_ids, edge.source_id, edge.target_id]
  end

  def collision_diagram
    ids = %w[state_diagram diagram_settings transition_0
             transition_0_details]
    states = ids.map { |id| Sirena::Diagram::StateNode.new(id: id) }
    transition = Sirena::Diagram::StateTransition.new(
      from_id: "state_diagram", to_id: "diagram_settings",
    )
    Sirena::Diagram::StateDiagram.new(
      states: states, transitions: [transition],
    )
  end

  it "preserves state, transition, and diagram semantics without mutation" do
    expect(semantic_summary).to eq(expected_semantic_summary)
  end

  it "preserves direct-model child containment and declaration order" do
    expected = [%w[parent child sibling], [nil, "parent", nil], %w[0 1 2]]
    expect(containment_summary).to eq(expected)
  end

  it "reserves collision-safe identities before generated records" do
    expect(collision_summary)
      .to eq([true, true, "state_diagram", "diagram_settings"])
  end
end
