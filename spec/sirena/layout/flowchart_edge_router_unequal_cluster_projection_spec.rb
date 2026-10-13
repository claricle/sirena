# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::FlowchartEdgeRouter do
  let(:source) do
    { x: 0, y: 10, width: 40, height: 20, metadata: { cluster: true } }
  end
  let(:target) do
    { x: 10, y: 0, width: 100, height: 150, metadata: { cluster: true } }
  end
  let(:points) { described_class.new.route(source, target).first }
  let(:bottom) { [source, target].map { |box| box[:y] + box[:height] }.max }

  it "routes the intermediate bends below both overlapping cluster faces" do
    intermediate_y = points[1...-1].map { |point| point[:y] }

    expect(intermediate_y).to all(be > bottom)
  end
end
