# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Quadrant do
  describe Sirena::Diagram::QuadrantPoint do
    subject(:point) { described_class.new(label: "Candidate", x: 0.25, y: 0.75) }

    describe "#valid?" do
      it "accepts coordinates at both inclusive boundaries" do
        expect(described_class.new(label: "Origin", x: 0.0, y: 0.0)).to be_valid
        expect(described_class.new(label: "Limit", x: 1.0, y: 1.0)).to be_valid
      end

      it "rejects a missing or empty label" do
        point.label = nil
        expect(point).not_to be_valid

        point.label = ""
        expect(point).not_to be_valid
      end

      it "rejects a missing coordinate" do
        point.x = nil
        expect(point).not_to be_valid

        point.x = 0.25
        point.y = nil
        expect(point).not_to be_valid
      end

      it "rejects coordinates outside the normalized range" do
        expect(described_class.new(label: "Left", x: -0.01, y: 0.5)).not_to be_valid
        expect(described_class.new(label: "Right", x: 1.01, y: 0.5)).not_to be_valid
        expect(described_class.new(label: "Below", x: 0.5, y: -0.01)).not_to be_valid
        expect(described_class.new(label: "Above", x: 0.5, y: 1.01)).not_to be_valid
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

  def point(label, x, y)
    Sirena::Diagram::QuadrantPoint.new(label: label, x: x, y: y)
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
      diagram = described_class.new(points: [point("A", 0.25, 0.75), point("B", 0.75, 0.25)])

      expect(diagram).to be_valid
    end

    it "rejects a chart when any point is invalid" do
      diagram = described_class.new(points: [point("Valid", 0.25, 0.75), point("", 0.75, 0.25)])

      expect(diagram).not_to be_valid
    end
  end

  describe "#points_by_quadrant" do
    it "groups points into all four quadrants" do
      points = [
        point("One", 0.75, 0.75),
        point("Two", 0.25, 0.75),
        point("Three", 0.25, 0.25),
        point("Four", 0.75, 0.25),
      ]

      expect(described_class.new(points: points).points_by_quadrant).to eq(
        1 => [points[0]],
        2 => [points[1]],
        3 => [points[2]],
        4 => [points[3]],
      )
    end

    it "keeps multiple points in the same quadrant in insertion order" do
      first = point("First", 0.75, 0.75)
      second = point("Second", 1.0, 1.0)

      grouped = described_class.new(points: [first, second]).points_by_quadrant

      expect(grouped).to eq(1 => [first, second])
    end
  end
end
