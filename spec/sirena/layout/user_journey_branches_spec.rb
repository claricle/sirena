# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::UserJourney do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::UserJourney.new }

  def task(name, score, actors = [])
    Sirena::Diagram::JourneyTask.new(name: name, score: score, actors: actors)
  end

  def section(name, tasks = [])
    Sirena::Diagram::JourneySection.new(name: name, tasks: tasks)
  end

  describe "graph branches" do
    it "uses the fallback id and complete metadata for an empty journey" do
      expect(graph).to include(
        id: "user_journey", children: [], edges: [],
        metadata: { title: nil, sections: [] },
      )
    end

    it "preserves an explicit diagram id and section metadata" do
      diagram.id = "checkout"
      diagram.title = "Checkout"
      diagram.sections << section("Find")

      expect(graph).to include(
        id: "checkout",
        metadata: { title: "Checkout", sections: ["Find"] },
      )
    end

    it "flattens sections into sequential nodes and cross-section edges" do
      diagram.sections << section("Find", [task("Browse", 5, ["Buyer"])])
      diagram.sections << section("Buy", [task("Pay", 3, ["Buyer", "Bank"])])

      expect(graph).to match(
        children: [hash_including(id: "task_0"), hash_including(id: "task_1")],
        edges: [hash_including(sources: ["task_0"], targets: ["task_1"])],
        metadata: hash_including(sections: %w[Find Buy]),
        id: "user_journey", layoutOptions: kind_of(Hash),
      )
    end

    it "carries task labels, score color, actors, and section index" do
      diagram.sections << section("Buy", [task("Pay", 3, ["Buyer", "Bank"])])

      expect(graph[:children].first).to match(
        id: "task_0", width: kind_of(Numeric), height: 80,
        labels: [hash_including(text: "Pay", position: :top),
                 hash_including(text: "3", position: :center),
                 hash_including(text: "Buyer, Bank", position: :bottom)],
        metadata: {
          name: "Pay", score: 3, score_color: :yellow,
          actors: ["Buyer", "Bank"], section_name: "Buy", section_index: 0,
        },
      )
    end

    it "uses minimum width for short content and measured width for long content" do
      long_name = "A task name long enough to exceed the minimum width"
      diagram.sections << section("Work", [task("A", 4), task(long_name, 4)])
      widths = graph[:children].map { |node| node[:width] }

      expect(widths).to satisfy { |short, long| short == 140 && long > short }
    end

    it "sets the complete horizontal journey layout policy" do
      expect(graph[:layoutOptions]).to include(
        "elk.algorithm" => "layered",
        "elk.direction" => "RIGHT",
        "elk.spacing.nodeNode" => 60,
        "elk.layered.spacing.nodeNodeBetweenLayers" => 60,
        "elk.layered.nodePlacement.strategy" => "SIMPLE",
        "elk.layered.considerModelOrder.strategy" => "NODES_AND_EDGES",
        "elk.hierarchyHandling" => "INCLUDE_CHILDREN",
      )
    end
  end
end
