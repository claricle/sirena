# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ElkPlacement do
  let(:edge) { { id: "dangling", sources: ["A"] } }
  let(:graph) { { edges: [edge] } }
  let(:received) { [] }
  let(:result) { Struct.new(:children, :edges).new }

  before do
    allow(Elkrb).to receive(:layout) do |*arguments|
      received.replace(arguments)
      result
    end
  end

  it "retains a sourced edge without a target in the ELK input" do
    returned = described_class.apply(graph)
    actual = [received.dig(0, :edges), received[1], returned.equal?(graph)]

    expect(actual).to eq([[edge], {}, true])
  end
end
