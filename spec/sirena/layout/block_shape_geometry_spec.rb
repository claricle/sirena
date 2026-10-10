# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  subject(:nodes) do
    described_class.new.call(diagram).children.to_h { |node| [node.id, node] }
  end

  let(:diagram) do
    blocks = [block("circle", "circle")] +
      %w[up down left right].map { |direction| arrow(direction) }
    Sirena::Diagram::Block.new(columns: 5, blocks: blocks)
  end

  def block(id, shape, direction = nil)
    Sirena::Diagram::BlockNode.new(
      id: id, label: id, shape: shape, direction: direction,
    )
  end

  def arrow(direction)
    block(direction, "arrow", direction)
  end

  it "publishes final circle geometry" do
    circle = nodes.fetch("circle")

    expect(circle).to have_attributes(
      center_x: 70.0, center_y: 50.0, radius: 30.0,
    )
  end

  it "publishes final points for every arrow direction" do
    expect(nodes.transform_values(&:shape_points)).to include(
      "up" => "190.0,20.0 240.0,80.0 140.0,80.0",
      "down" => "260.0,20.0 360.0,20.0 310.0,80.0",
      "left" => "380.0,50.0 480.0,20.0 480.0,80.0",
      "right" => "500.0,20.0 600.0,50.0 500.0,80.0",
    )
  end
end
