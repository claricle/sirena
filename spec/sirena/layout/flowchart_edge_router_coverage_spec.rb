# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::FlowchartEdgeRouter do
  subject(:router) { described_class.new }

  let(:boxes) { FlowchartRouterBoxes }

  describe "a cluster end that sits on no border" do
    let(:round_cluster) do
      boxes.cluster([0, 0], [100, 200], shape: "circle")
    end

    it "leaves the end where the loop put it" do
      points, = router.route(round_cluster, round_cluster)

      expect(points.first).to eq({ x: 50.0, y: 50.0 })
    end
  end

  describe "a loop on a circle node" do
    let(:circle) { boxes.box([0, 0], [100, 200], shape: "circle") }

    it "leaves from the top of the circle, not of its box" do
      points, = router.route(circle, circle)

      expect(points.first).to eq({ x: 50.0, y: 50.0 })
    end

    it "returns to the bottom of the circle" do
      points, = router.route(circle, circle)

      expect(points.last).to eq({ x: 50.0, y: 150.0 })
    end
  end

  describe "a bend that coincides with a cluster corner" do
    let(:source) { boxes.cluster([0, 0], [100, 100]) }
    let(:target) { boxes.cluster([75, 25], [100, 100]) }

    it "keeps the corner instead of rounding it" do
      points, = router.route(source, target, [{ x: 0, y: 100 }])

      expect(points.first).to eq({ x: 0.0, y: 100.0 })
    end

    it "rounds the same corner when the bend lies elsewhere" do
      points, = router.route(source, target)

      expect(points.first).to eq({ x: 0.0, y: 95.0 })
    end
  end
end
