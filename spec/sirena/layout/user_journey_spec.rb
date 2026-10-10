# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/user_journey"
require "sirena/diagram/user_journey"

RSpec.describe Sirena::Layout::UserJourney do
  let(:transform) { described_class.new }

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
      diagram = Sirena::Diagram::UserJourney.new.tap do |d|
        d.title = "My Journey"
        section = Sirena::Diagram::JourneySection.new.tap do |s|
          s.name = "Shopping"
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = "Browse"
            t.score = 5
            t.actors = ["Customer"]
          end
        end
        d.sections << section
      end

      scene = transform.to_graph(diagram)

      expect(scene).to be_a(described_class::Scene)
      expect(scene.id).to eq("user_journey")
      expect(scene.tasks).to be_a(Array)
      expect(scene.arrows).to be_a(Array)
      expect(scene.view_box).to eq("0 -25 500 540")
    end

    it "creates task nodes with dimensions" do
      diagram = Sirena::Diagram::UserJourney.new.tap do |d|
        section = Sirena::Diagram::JourneySection.new.tap do |s|
          s.name = "Shopping"
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = "Browse"
            t.score = 5
            t.actors = ["Customer"]
          end
        end
        d.sections << section
      end

      scene = transform.to_graph(diagram)

      expect(scene.tasks.length).to eq(1)
      task = scene.tasks.first
      expect(task.id).to eq("task_0")
      expect(task.box.width).to be > 0
      expect(task.box.height).to be > 0
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
