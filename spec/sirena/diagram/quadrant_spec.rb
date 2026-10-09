# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Quadrant do
  describe Sirena::Diagram::QuadrantPoint do
    subject(:point) do
      described_class.new(label: "Candidate", x: 0.25, y: 0.75)
    end

    describe "#valid?" do
      def validities(*coordinates)
        coordinates.map do |x_position, y_position|
          described_class.new(label: "Point", x: x_position,
                              y: y_position).valid?
        end
      end

      it "accepts coordinates at both inclusive boundaries" do
        points = [described_class.new(label: "Origin", x: 0.0, y: 0.0),
                  described_class.new(label: "Limit", x: 1.0, y: 1.0)]
        expect(points).to all(be_valid)
      end

      it "rejects a missing or empty label" do
        points = [described_class.new(x: 0.25, y: 0.75),
                  described_class.new(label: "", x: 0.25, y: 0.75)]
        expect(points.map(&:valid?)).to eq([false, false])
      end

      it "rejects a missing coordinate" do
        points = [described_class.new(label: "X", y: 0.75),
                  described_class.new(label: "Y", x: 0.25)]
        expect(points.map(&:valid?)).to eq([false, false])
      end

      it "rejects coordinates outside the normalized range" do
        outside = [[-0.01, 0.5], [1.01, 0.5], [0.5, -0.01], [0.5, 1.01]]

        expect(validities(*outside)).to eq([false, false, false, false])
      end
    end

    describe "#quadrant" do
      it "returns 1 for the top-right, including both midlines" do
        expect(described_class.new(x: 0.5, y: 0.5).quadrant).to eq(1)
      end

      it "returns 2 for the top-left" do
        expect(described_class.new(x: 0.49, y: 0.5).quadrant).to eq(2)
      end

      it "returns 3 for the bottom-left" do
        expect(described_class.new(x: 0.49, y: 0.49).quadrant).to eq(3)
      end

      it "returns 4 for the bottom-right" do
        expect(described_class.new(x: 0.5, y: 0.49).quadrant).to eq(4)
      end
    end
  end

  def point(label, x_position, y_position)
    Sirena::Diagram::QuadrantPoint.new(
      label: label, x: x_position, y: y_position,
    )
  end

  describe "#diagram_type" do
    it "returns :quadrant" do
      expect(described_class.new.diagram_type).to eq(:quadrant)
    end
  end

  describe "#valid?" do
    it "accepts an empty chart" do
      expect(described_class.new).to be_valid
    end

    it "accepts a chart when every point is valid" do
      points = [point("A", 0.25, 0.75), point("B", 0.75, 0.25)]
      diagram = described_class.new(points: points)

      expect(diagram).to be_valid
    end

    it "rejects a chart when any point is invalid" do
      points = [point("Valid", 0.25, 0.75), point("", 0.75, 0.25)]
      diagram = described_class.new(points: points)

      expect(diagram).not_to be_valid
    end
  end

  describe "#points_by_quadrant" do
    let(:quadrant_points) do
      [point("One", 0.75, 0.75), point("Two", 0.25, 0.75),
       point("Three", 0.25, 0.25), point("Four", 0.75, 0.25)]
    end

    let(:expected_groups) do
      { 1 => [quadrant_points[0]], 2 => [quadrant_points[1]],
        3 => [quadrant_points[2]], 4 => [quadrant_points[3]] }
    end

    it "groups points into all four quadrants" do
      grouped = described_class.new(points: quadrant_points).points_by_quadrant

      expect(grouped).to eq(expected_groups)
    end

    it "keeps multiple points in the same quadrant in insertion order" do
      first = point("First", 0.75, 0.75)
      second = point("Second", 1.0, 1.0)

      grouped = described_class.new(points: [first, second]).points_by_quadrant

      expect(grouped).to eq(1 => [first, second])
    end
  end
end
