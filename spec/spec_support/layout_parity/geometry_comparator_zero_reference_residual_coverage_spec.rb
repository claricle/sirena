# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::GeometryComparator do
  subject(:comparison) do
    pair = [element("line", box(0)), element("line", box(5))]
    reference = figure_class.new(elements: [pair.first], root_box: box(100))
    described_class.compare(reference:, pairs: [pair])
  end

  let(:box_class) { SpecSupport::LayoutParity::Bbox }
  let(:element_class) { SpecSupport::LayoutParity::Element }
  let(:figure_class) { SpecSupport::LayoutParity::Figure }

  def box(width)
    box_class.from_extent(0, 0, width, 10)
  end

  def element(key, bbox)
    element_class.new(kind: :node, key:, bbox:)
  end

  it "makes growth from a zero reference width infinitely wrong" do
    expect(comparison.values_at(:worst_e_w, :worst_e_a))
      .to eq([Float::INFINITY, Float::INFINITY])
  end
end
