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
end
