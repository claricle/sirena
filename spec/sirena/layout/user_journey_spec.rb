# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/user_journey"
require "sirena/diagram/user_journey"

RSpec.describe Sirena::Layout::UserJourney do
  let(:transform) { described_class.new }
  let(:positive_box) do
    have_attributes(width: be_positive, height: be_positive)
  end
  let(:single_task_journey) do
    Sirena::Diagram::UserJourney.new(
      title: "My Journey",
      sections: [
        Sirena::Diagram::JourneySection.new(
          name: "Shopping",
          tasks: [
            Sirena::Diagram::JourneyTask.new(
              name: "Browse", score: 5, actors: ["Customer"],
            ),
          ],
        ),
      ],
    )
  end

  def representative_journey
    Sirena::Diagram::UserJourney.new(
      id: "checkout", title: "Checkout",
      sections: [
        Sirena::Diagram::JourneySection.new(
          name: "Find",
          tasks: [Sirena::Diagram::JourneyTask.new(
            name: "Browse", score: 5, actors: ["Buyer"],
          )],
        ),
        Sirena::Diagram::JourneySection.new(
          name: "Buy",
          tasks: [Sirena::Diagram::JourneyTask.new(
            name: "Pay", score: 2, actors: ["Buyer", "Bank"],
          )],
        ),
      ]
    )
  end

  describe "#to_graph" do
    it "converts diagram to graph structure" do
      scene = transform.to_graph(single_task_journey)

      expect(scene).to be_a(described_class::Scene).and have_attributes(
        id: "user_journey", tasks: be_a(Array), arrows: be_a(Array),
        view_box: "0 -25 500 540"
      )
    end

    it "creates task nodes with dimensions" do
      task = transform.to_graph(single_task_journey).tasks.fetch(0)

      expect(task).to have_attributes(
        id: "task_0", box: positive_box,
      )
    end

    it "draws one timeline arrow at the mmdc height" do
      scene = transform.to_graph(representative_journey)

      expect(scene.arrows.map { |arrow| arrow.line.y1 }).to eq([200])
    end

    it "ends the timeline arrow short of the right margin" do
      scene = transform.to_graph(representative_journey)

      expect(scene.arrows.first.line.x2).to eq(546)
    end

    it "names each task after its label" do
      scene = transform.to_graph(representative_journey)

      expect(scene.tasks.map { |task| task.labels.map(&:text) })
        .to eq([["Browse"], ["Pay"]])
    end

    it "gives each task one dot per actor, in written order" do
      scene = transform.to_graph(representative_journey)

      expect(scene.tasks.last.dots.map(&:name)).to eq(["Buyer", "Bank"])
    end

    it "labels each section band" do
      scene = transform.to_graph(representative_journey)

      expect(scene.sections.flat_map { |s| s.labels.map(&:text) })
        .to eq(["Find", "Buy"])
    end

    it "lists the actors alphabetically in the legend" do
      scene = transform.to_graph(representative_journey)

      expect(scene.legend.map { |actor| actor.dot.name })
        .to eq(["Bank", "Buyer"])
    end

    it "puts the first task at the left margin below the bands" do
      scene = transform.to_graph(representative_journey)

      expect([scene.tasks.first.box.x, scene.tasks.first.box.y])
        .to eq([150.0, 110.0])
    end

    it "spaces task columns 200px apart" do
      scene = transform.to_graph(representative_journey)

      expect(scene.tasks.map { |task| task.box.x }).to eq([150.0, 350.0])
    end

    it "raises error for invalid diagram" do
      # An empty journey (no sections) is valid on its own -- mmdc renders
      # it -- so invalidity here must come from a section that fails its
      # own #valid? check.
      diagram = Sirena::Diagram::UserJourney.new
      diagram.sections << Sirena::Diagram::JourneySection.new

      expect { transform.to_graph(diagram) }.to raise_error(
        Sirena::Layout::LayoutError,
      )
    end

    it "lays out private and shared graph inputs to identical scenes" do
      diagram = representative_journey
      ir = Sirena::Notation::Mermaid::IRAdapters::UserJourney.call(diagram)

      expect(Marshal.dump(transform.to_graph(ir)))
        .to eq(Marshal.dump(transform.to_graph(diagram)))
    end
  end
end
