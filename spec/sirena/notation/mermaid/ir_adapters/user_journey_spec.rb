# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/user_journey"
require "sirena/diagram/user_journey"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::UserJourney do
  def task(name, score, actors)
    Sirena::Diagram::JourneyTask.new(
      name: name, score: score, actors: actors,
    )
  end

  def section(name, tasks)
    Sirena::Diagram::JourneySection.new(name: name, tasks: tasks)
  end

  def journey
    Sirena::Diagram::UserJourney.new(
      id: "task_0", title: "Checkout",
      sections: [
        section("Discover", [task("Browse", 5, ["Buyer"])]),
        section("Purchase", [task("Pay", 2, ["Buyer", "Bank"])]),
      ]
    ).tap do |diagram|
      diagram.define_singleton_method(:acc_title) { "Checkout journey" }
      diagram.define_singleton_method(:acc_description) do
        "A buyer discovers and purchases an item"
      end
    end
  end

  subject(:ir) { described_class.call(journey) }

  let(:expected_graph_summary) do
    [true, "task_0", "Checkout", "customer_journey", "Checkout journey",
     "A buyer discovers and purchases an item"]
  end

  let(:expected_node_attributes) do
    [
      %w[section_0 task_0_2 task_0_2_actor_0 section_1 task_1] +
        %w[task_1_actor_0 task_1_actor_1],
      ["Discover", "Browse", "Buyer", "Purchase", "Pay", "Buyer", "Bank"],
      %w[journey_section journey_task_green journey_actor journey_section] +
        %w[journey_task_red journey_actor journey_actor],
      [nil, "section_0", "task_0_2", nil, "section_1", "task_1", "task_1"],
      [nil, 5.0, nil, nil, 2.0, nil, nil],
    ]
  end

  def graph_summary
    [ir.valid?, ir.id, ir.label, ir.role, ir.accessibility_title,
     ir.accessibility_description]
  end

  def node_attributes
    %i[id label role parent_id].map { |name| node_values(name) } +
      [ir.nodes.map { |node| node.properties.weight }]
  end

  def node_values(name)
    ir.nodes.map { |node| node.public_send(name) }
  end

  def collision_graph
    collision = journey
    collision.id = "flow_0"
    described_class.call(collision)
  end

  def graph_ids(graph)
    [graph.id] + graph.nodes.map(&:id) + graph.edges.map(&:id)
  end

  it "builds a valid graph with title and accessibility metadata" do
    expect(graph_summary).to eq(expected_graph_summary)
  end

  it "preserves ordered sections, tasks, scores, styles, and actors" do
    expect(node_attributes).to eq(expected_node_attributes)
  end

  it "connects sequential task identities across section boundaries" do
    edge = ir.edges.fetch(0)

    expect([edge.id, edge.source_id, edge.target_id, edge.role])
      .to eq(["flow_0", "task_0_2", "task_1", "sequence"])
  end

  it "reserves collision-safe root, node, and edge identities" do
    graph = collision_graph
    ids = graph_ids(graph)
    expect([graph.edges.fetch(0).id, ids.uniq.length, ids.length])
      .to eq(["flow_0_2", 9, 9])
  end

  it "keeps canvas geometry out of the shared graph" do
    expect(ir.nodes).to all(
      satisfy { |node| !node.respond_to?(:x) && !node.respond_to?(:width) },
    )
  end
end
