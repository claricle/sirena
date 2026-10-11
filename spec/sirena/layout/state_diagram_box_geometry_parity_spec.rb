# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram, :aggregate_failures do
  let(:parser) { Sirena::Parser::StateDiagram.new }
  let(:layout) { described_class.new }

  context "with the declaration-only corpus case" do
    let(:source) do
      File.read(
        File.expand_path(
          "../../mermaid/state_diagram/" \
          "assemble_assemblies_state_assemble_state_assembl-d98dd4e2.mmd",
          __dir__,
        ),
      )
    end
    let(:scene) { layout.to_graph(parser.parse(source)) }

    it "uses the pinned browser dimensions for ordinary one-line states" do
      dimensions = scene.children.to_h do |state|
        [state.id, [state.width, state.height]]
      end

      expect(dimensions).to eq(
        "assemble" => [81.734375, 40.0],
        "assemblies" => [92.765625, 40.0],
      )
    end
  end

  context "with the nested-composite corpus case" do
    let(:source) do
      File.read(
        File.expand_path(
          "../../mermaid/state_diagram/" \
          "should_handle_notes_for_composite_nested_states-0033e4b1.mmd",
          __dir__,
        ),
      )
    end
    let(:scene) { layout.to_graph(parser.parse(source)) }
    let(:composite) { scene.children.find { |state| state.id == "NotShooting" } }

    it "preserves the composite, note, and terminal dimensions" do
      dimensions = scene.children.to_h do |state|
        [state.id, [state.width, state.height]]
      end

      expect(dimensions).to eq(
        "start_1" => [30.0, 30.0],
        "NotShooting" => [238.734375, 343.0],
        "NotShooting----note" => [230.0, 78.0],
      )
    end

    it "preserves the nested transition topology" do
      expect(composite.children.map(&:id)).to eq(%w[Idle Configuring start_2])
      expect(scene.edges.map { |edge| [edge.source, edge.target] }).to eq(
        [["start_1", "NotShooting"], ["start_2", "Idle"],
         ["Idle", "Configuring"], ["Configuring", "Idle"]],
      )
    end
  end
end
