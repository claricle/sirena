# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Diagram do
  it "identifies a diagram with participants" do
    diagram = described_class.new(participants: ["A"], items: [])
    identity = [diagram.valid?, diagram.diagram_type]
    expect(identity).to eq([true, :sequence_diagram])
  end
end
