# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::StateDiagram do
  it "is invalid when a transition leaves an unknown state" do
    state = Sirena::Diagram::StateNode.new(id: "A", state_type: "normal")
    ghost = Sirena::Diagram::StateTransition.new(from_id: "Z", to_id: "A")
    expect(described_class.new(states: [state], transitions: [ghost]))
      .not_to be_valid
  end
end
