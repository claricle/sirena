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
      expect(scene.view_box).to eq("0 0 270 290")
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

    it "creates sequential edges between tasks" do
      diagram = Sirena::Diagram::UserJourney.new.tap do |d|
        section = Sirena::Diagram::JourneySection.new.tap do |s|
          s.name = "Shopping"
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = "Browse"
            t.score = 5
            t.actors = ["Customer"]
          end
          s.tasks << Sirena::Diagram::JourneyTask.new.tap do |t|
            t.name = "Select"
            t.score = 4
            t.actors = ["Customer"]
          end
        end
        d.sections << section
      end

      scene = transform.to_graph(diagram)

      expect(scene.arrows.length).to eq(1)
      arrow = scene.arrows.first
      expect(arrow.id).to eq("flow_0")
      expect([arrow.line.x1, arrow.line.x2]).to eq([190.0, 300.0])
    end

    it "includes task metadata" do
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

      expect(scene.tasks.first.labels.map(&:text)).to eq(
        ["Browse", "5", "Customer"],
      )
      expect(scene.sections.map(&:text)).to eq(["Shopping"])
    end

    it "publishes final grid positions" do
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

      expect([scene.tasks.first.box.x, scene.tasks.first.box.y])
        .to eq([50.0, 50.0])
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
