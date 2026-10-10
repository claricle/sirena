# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::StateNode do
  it "identifies fork and join nodes" do
    nodes = %w[fork join].map do |state_type|
      described_class.new(id: state_type, state_type: state_type)
    end

    predicates = nodes.map { |node| [node.fork_state?, node.join_state?] }
    expect(predicates).to eq([[true, false], [false, true]])
  end
end
