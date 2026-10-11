# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence do
  def scene_for(fixture)
    source = File.read(File.join(__dir__, "../../mermaid/sequence", fixture))
    diagram = Sirena::Parser::Sequence.new.parse(source)

    described_class.new.call(diagram)
  end

  def participant_geometry(fixture)
    scene_for(fixture).participants.map do |participant|
      [participant.x, participant.width]
    end
  end

  def wonderland_cases
    %w[
      sequencediagram_spec-ab7b0e29.mmd
      sequencediagram_spec-491a3b83.mmd
    ]
  end

  it "matches participant widths for the Wonderland corpus duplicates" do
    evidence = wonderland_cases.map { |fixture| participant_geometry(fixture) }
    expected = [[50.0, 156.0], [293.0, 150.0]]
    expect(evidence).to eq(Array.new(2, expected))
  end

  it "matches actor gaps for the create and destroy corpus case" do
    scene = scene_for("sequencediagram_spec-690f7aca.mmd")

    expect(scene.participants.map(&:x)).to eq([50.0, 290.0, 565.0, 840.0])
  end
end
