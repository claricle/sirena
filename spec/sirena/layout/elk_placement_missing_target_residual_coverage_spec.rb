# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ElkPlacement do
  it "retains a sourced edge without a target in the ELK input" do
    edge = { id: "dangling", sources: ["A"] }
    graph = { edges: [edge] }
    received = []
    result = Struct.new(:children, :edges).new
    allow(Elkrb).to receive(:layout) do |*arguments|
      received.replace(arguments)
      result
    end

    returned = described_class.apply(graph)
    actual = [received.dig(0, :edges), received[1], returned.equal?(graph)]

    expect(actual).to eq([[edge], {}, true])
  end
end
