# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::SpatialInvariantChecker do
  let(:bbox_class) { SpecSupport::LayoutParity::Bbox }
  let(:parent_box) { bbox_class.from_extent(0, 0, 20, 20) }
  let(:child_box) { bbox_class.from_extent(5, 5, 5, 5) }
  let(:pairs) { [pair("child", child_box), pair("parent", parent_box)] }

  def pair(key, bbox)
    element = SpecSupport::LayoutParity::Element.new(kind: :node, key:, bbox:)
    [element, element]
  end

  it "preserves containment when the child precedes its parent" do
    expect(described_class.check(pairs:)).to be_empty
  end
end
