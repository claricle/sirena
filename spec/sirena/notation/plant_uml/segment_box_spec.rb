# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::SegmentBox do
  let(:box) { [0.0, 0.0, 10.0, 10.0] }

  describe ".within?" do
    it "holds for a segment across the box" do
      expect(described_class.within?(box, [5, -5], [5, 15], 0.0)).to be(true)
    end

    it "holds for a segment beside the box within the gap" do
      expect(described_class.within?(box, [14, -5], [14, 15], 4.0)).to be(true)
    end

    it "fails for a segment beside the box beyond the gap" do
      expect(described_class.within?(box, [14, -5], [14, 15], 3.9))
        .to be(false)
    end

    it "measures a corner of the box straight, not along each axis" do
      expect(described_class.within?(box, [20, 14], [14, 20], 5.0))
        .to be(false)
    end

    it "holds for a segment that passes a corner within the gap" do
      expect(described_class.within?(box, [10, 17], [17, 10], 5.0))
        .to be(true)
    end

    it "measures from an end of the segment to the box" do
      expect(described_class.within?(box, [13, 14], [30, 40], 5.0)).to be(true)
    end

    it "measures a point as a segment of no length" do
      expect(described_class.within?(box, [13, 14], [13, 14], 4.9))
        .to be(false)
    end
  end
end
