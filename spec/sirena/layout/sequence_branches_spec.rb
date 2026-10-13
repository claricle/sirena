# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"
require "sirena/layout/sequence"

RSpec.describe Sirena::Layout::Sequence do
  def scene_for(source)
    diagram = Sirena::Parser::Sequence.new.parse(source)
    described_class.new.call(diagram)
  end

  it "returns a finite scene for an empty shared graph" do
    graph = Sirena::IR::Graph.new(id: "sequence", role: "interaction_graph")
    scene = described_class.new.call(graph)

    expect(scene).to have_attributes(
      width: 40.0, height: 40.0, participants: [], messages: [],
    )
  end

  it "omits heads and labels for an empty headless message" do
    message = scene_for("sequenceDiagram\n  A->B:\n").messages.first

    expect(message).to have_attributes(heads: [], label: nil)
  end

  it "builds the actor-specific head and body geometry" do
    actor = scene_for("sequenceDiagram\n  actor A\n").participants.first

    expect([actor.actor_head.class, actor.actor_lines.length])
      .to eq([described_class::Circle, 4])
  end

  context "with the stick figure of an actor" do
    let(:actor) do
      scene_for("sequenceDiagram\n  actor A\n").participants.first
    end
    let(:xs) { actor.actor_lines.flat_map { |l| [l.x1, l.x2] } }
    let(:ys) do
      actor.actor_lines.flat_map { |l| [l.y1, l.y2] } +
        [actor.actor_head.y - actor.actor_head.radius]
    end

    it "draws it at the width mmdc gives it" do
      expect(xs.max - xs.min).to eq(36)
    end

    it "draws it at the height mmdc gives it" do
      expect(ys.max - ys.min).to eq(65)
    end

    it "draws its head at the radius mmdc gives it" do
      expect(actor.actor_head.radius).to eq(15)
    end
  end
end
