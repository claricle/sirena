# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  subject(:states) do
    source = File.read(
      "spec/mermaid/state_diagram/" \
      "assemble_assemblies_state_assemble_state_assembl-d98dd4e2.mmd",
    )
    diagram = Sirena::Parser::StateDiagram.new.parse(source)
    described_class.new.to_graph(diagram).children
  end

  let(:expected_geometry) do
    [
      [
        ["assemble", "normal", 8.0, 8.0],
        ["assemblies", "normal", 139.734375, 8.0],
      ],
      50.0,
    ]
  end

  def pair_geometry(states)
    first, second = states
    [
      states.map { |state| [state.id, state.shape_type, state.x, state.y] },
      second.x - first.x - first.width,
    ]
  end

  it "packs two disconnected ordinary states like Mermaid" do
    expect(pair_geometry(states)).to eq(expected_geometry)
  end
end
