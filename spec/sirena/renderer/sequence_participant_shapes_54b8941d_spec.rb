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

  it "draws the typed participant symbols at their lifeline centers" do
    participants = scene.participants.to_h { |item| [item.id, item] }

    expect(participants["Charlie"].shape_circle)
      .to have_attributes(x: 125, y: 43, radius: 22)
    expect(participants["Charlie"].shape_lines.first)
      .to have_attributes(x1: 70, y1: 43, x2: 110, y2: 43)
    expect(participants["David"].shape_circle)
      .to have_attributes(x: 325, y: 42, radius: 22)
    expect(participants["Eve"].shape_circle)
      .to have_attributes(x: 525, y: 41, radius: 22)
    expect(participants["Eve"].shape_lines.first)
      .to have_attributes(x1: 503, y1: 63, x2: 547, y2: 63)
  end

  it "renders circles and type-specific marks instead of participant boxes" do
    xml = Sirena.render(source)

    %w[Charlie David Eve].each do |id|
      group = xml[%r{<g id="participant-#{id}".*?</g>}m]
      expect(group).to include("<circle")
      expect(group).not_to include("<rect")
    end
  end
end
