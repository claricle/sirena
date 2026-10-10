# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4Intersection do
  let(:box) do
    ->(x_pos, y_pos) { double(x: x_pos, y: y_pos, width: 100, height: 50) }
  end

  def rounded(points)
    points.map { |pair| pair.map { |value| value.round(1) } }
  end

  it "leaves a box on its side when the other centre is level with its top" do
    expect(described_class.points(box.(0, 25), box.(300, 0)))
      .to eq([[100, 50], [300, 35]])
  end

  it "leaves from the side edge on a shallow slope" do
    points = described_class.points(box.(0, 0), box.(300, 100))
    expect(rounded(points)).to eq([[100.0, 42.9], [300.0, 110.0]])
  end

  it "leaves from the top or bottom edge on a steep slope" do
    points = described_class.points(box.(0, 0), box.(100, 300))
    expect(rounded(points)).to eq([[61.5, 50.0], [145.5, 300.0]])
  end

  it "never returns a nil point" do
    points = described_class.points(box.(0, 0), box.(0, 0))
    expect(points.flatten).to all(be_a(Numeric))
  end
end
