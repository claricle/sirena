# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/mindmap_cose_body"
require "sirena/layout/mindmap_cose_geometry"

module MindmapCoseGeometryHelpers
  def box(x_position, y_position)
    Sirena::Layout::MindmapCoseBody.new("box", 40, 20).tap do |body|
      body.x = x_position
      body.y = y_position
    end
  end
end

# Expected values follow IGeometry.calcSeparationAmount in layout-base 1.0.2,
# worked by hand from its source.
RSpec.describe Sirena::Layout::MindmapCoseGeometry do
  include MindmapCoseGeometryHelpers

  describe ".separation" do
    it "assumes a 45 degree slope when both centres coincide" do
      expect(described_class.separation(box(0.0, 0.0), box(0.0, 0.0), 25.0))
        .to eq([-35.0, -35.0])
    end

    it "separates on the horizontal overlap when the centres are near level" do
      expect(described_class.separation(box(0.0, 0.0), box(10.0, 2.0), 25.0))
        .to eq([40.0, 28.0])
    end

    it "separates on the vertical overlap when the centres are steeper" do
      expect(described_class.separation(box(0.0, 0.0), box(10.0, 10.0), 25.0))
        .to eq([30.0, 30.0])
    end
  end
end
