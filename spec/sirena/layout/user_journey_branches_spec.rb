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

  def checkout_diagram
    diagram.id = "checkout"
    diagram.title = "Checkout"
    diagram.sections << section("Find")
  end

  def two_section_journey
    diagram.sections << section("Find", [task("Browse", 5, ["Buyer"])])
    diagram.sections << section("Buy", [task("Pay", 3, ["Buyer", "Bank"])])
  end

  def task_widths
    long_name = "A task name long enough to exceed the minimum width"
    diagram.sections << section("Work", [task("A", 4), task(long_name, 4)])
    graph.tasks.map { |node| node.box.width }
  end

  def flattened_scene_summary
    arrow = graph.arrows.first
    [graph.tasks.map(&:id), [arrow.source, arrow.target],
     graph.sections.map(&:text)]
  end

  def pay_task_summary
    journey_task = graph.tasks.first
    [[journey_task.id, journey_task.box.width,
      journey_task.box.height, journey_task.box.style],
     journey_task.labels.map(&:text),
     [journey_task.section_name, journey_task.section_index]]
  end

  def journey_layout_policy
    {
      "elk.algorithm" => "layered",
      "elk.direction" => "RIGHT",
      "elk.spacing.nodeNode" => 60,
      "elk.layered.spacing.nodeNodeBetweenLayers" => 60,
      "elk.layered.nodePlacement.strategy" => "SIMPLE",
      "elk.layered.considerModelOrder.strategy" => "NODES_AND_EDGES",
      "elk.hierarchyHandling" => "INCLUDE_CHILDREN",
    }
  end

  describe "graph branches" do
    it "uses the fallback id and complete metadata for an empty journey" do
      expect([graph.id, graph.title, graph.sections, graph.tasks, graph.arrows])
        .to eq(["user_journey", nil, [], [], []])
    end

    it "preserves an explicit diagram id and section metadata" do
      checkout_diagram

      expect([graph.id, graph.title.text, graph.sections.map(&:text)])
        .to eq(["checkout", "Checkout", ["Find"]])
    end

    it "flattens sections into sequential nodes and cross-section edges" do
      two_section_journey
      expect(flattened_scene_summary)
        .to eq([%w[task_0 task_1], %w[task_0 task_1], %w[Find Buy]])
    end

    it "carries task labels, score color, actors, and section index" do
      diagram.sections << section("Buy", [task("Pay", 3, ["Buyer", "Bank"])])
      expect(pay_task_summary).to match(
        [["task_0", kind_of(Numeric), 80, "yellow"],
         ["Pay", "3", "Buyer, Bank"], ["Buy", 0]],
      )
    end

    it "uses minimum width for short content, measured for long content" do
      short_width, long_width = task_widths

      expect([short_width, long_width > short_width]).to eq([140, true])
    end

    it "sets the complete horizontal journey layout policy" do
      layout_options = described_class.new.build_graph(diagram)[:layoutOptions]

      expect(layout_options).to include(journey_layout_policy)
    end
  end
end
