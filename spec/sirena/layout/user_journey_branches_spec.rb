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

  def band_names
    graph.sections.flat_map { |band| band.labels.map(&:text) }
  end

  def pay_task_summary
    [task_box_facts, task_label_facts, task_section_facts]
  end

  def task_box_facts
    box = graph.tasks.first.box
    [graph.tasks.first.id, box.width, box.height, box.fill]
  end

  def task_label_facts
    journey_task = graph.tasks.first
    [journey_task.labels.map(&:text), journey_task.dots.map(&:name)]
  end

  def task_section_facts
    journey_task = graph.tasks.first
    [journey_task.section_name, journey_task.section_index]
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

  def from_graph_scenes
    two_section_journey
    positioned = described_class.new.build_graph(diagram)
    Sirena::Layout::Grid.apply(positioned)
    ir = Sirena::Notation::Mermaid::IRAdapters::UserJourney.call(diagram)
    [described_class.from_graph(positioned), described_class.from_graph(ir)]
  end

  describe "graph branches" do
    it "uses the fallback id and complete metadata for an empty journey" do
      expect([graph.id, graph.title, graph.sections, graph.tasks,
              graph.arrows.map(&:id)])
        .to eq(["user_journey", nil, [], [], ["timeline"]])
    end

    it "keeps the diagram id and title, and bands only sections with tasks" do
      checkout_diagram

      expect([graph.id, graph.title.text, band_names])
        .to eq(["checkout", "Checkout", []])
    end

    it "keeps tasks in written order, one band per section" do
      two_section_journey
      expect([graph.tasks.map(&:id), band_names])
        .to eq([%w[task_0 task_1], %w[Find Buy]])
    end

    it "carries task label, section colour, actors, and section index" do
      diagram.sections << section("Buy", [task("Pay", 3, ["Buyer", "Bank"])])
      expect(pay_task_summary).to eq(
        [["task_0", 150.0, 50.0, "#191970"],
         [["Pay"], ["Buyer", "Bank"]], ["Buy", 0]],
      )
    end

    it "gives every task the same 150px box whatever its name" do
      expect(task_widths).to eq([150.0, 150.0])
    end

    it "sets the complete horizontal journey layout policy" do
      layout_options = described_class.new.build_graph(diagram)[:layoutOptions]

      expect(layout_options).to include(journey_layout_policy)
    end

    it "retains from_graph behavior for positioned hashes and shared IR" do
      from_hash, from_ir = from_graph_scenes
      expect(Marshal.dump(from_hash)).to eq(Marshal.dump(from_ir))
    end
  end
end
