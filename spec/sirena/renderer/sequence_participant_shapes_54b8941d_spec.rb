# frozen_string_literal: true

require "spec_helper"

# Geometry from the pinned sequencediagram_v2_spec-54b8941d reference.
RSpec.describe Sirena::Renderer::Sequence, :aggregate_failures do
  let(:source) do
    <<~MERMAID
      sequenceDiagram
        participant Charlie@{"type":"boundary"}
        participant David@{"type":"control"}
        participant Eve@{"type":"entity"}
    MERMAID
  end
  let(:scene) do
    diagram = Sirena::Parser::Sequence.new.parse(source)
    Sirena::Layout::Sequence.new.to_graph(diagram)
  end

  let(:participants) { scene.participants.to_h { |item| [item.id, item] } }

  it "draws Charlie's circle at its lifeline center" do
    expect(participants["Charlie"].shape_circle)
      .to have_attributes(x: 125, y: 43, radius: 22)
  end

  it "draws Charlie's boundary line beside its circle" do
    expect(participants["Charlie"].shape_lines.first)
      .to have_attributes(x1: 70, y1: 43, x2: 110, y2: 43)
  end

  it "draws David's circle at its lifeline center" do
    expect(participants["David"].shape_circle)
      .to have_attributes(x: 325, y: 42, radius: 22)
  end

  it "draws Eve's circle at its lifeline center" do
    expect(participants["Eve"].shape_circle)
      .to have_attributes(x: 525, y: 41, radius: 22)
  end

  it "draws Eve's entity line under its circle" do
    expect(participants["Eve"].shape_lines.first)
      .to have_attributes(x1: 503, y1: 63, x2: 547, y2: 63)
  end

  %w[Charlie David Eve].each do |id|
    it "renders #{id} as a circle with marks instead of a box" do
      group = Sirena.render(source)[%r{<g id="participant-#{id}".*?</g>}m]

      expect(group).to include("<circle")
      expect(group).not_to include("<rect")
    end
  end
end
