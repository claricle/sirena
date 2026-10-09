# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::FlowchartEdgeRouter do
  subject(:router) { described_class.new }

  def box(x_coordinate: 0, y_coordinate: 0, width: 100, height: 50,
          cluster: false)
    {
      x: x_coordinate,
      y: y_coordinate,
      width: width,
      height: height,
      metadata: { cluster: cluster },
    }
  end

  def point(x_coordinate, y_coordinate)
    { x: x_coordinate, y: y_coordinate }
  end

  def expect_route(source, target, points:, label_segment:)
    expect(router.route(source, target)).to eq([points, label_segment])
  end

  def overlapping_cluster_boxes
    source = box(width: 100, height: 100, cluster: true)
    target = box(x_coordinate: 75, y_coordinate: 25, width: 100,
                 height: 100, cluster: true)
    [source, target]
  end

  def nested_cluster_boxes
    source = box(width: 200, height: 200, cluster: true)
    target = box(x_coordinate: 50, y_coordinate: 50, width: 50, height: 50,
                 cluster: true)
    [source, target]
  end

  def diagonal_cluster_boxes
    source = box(width: 100, height: 100, cluster: true)
    target = box(x_coordinate: 200, y_coordinate: 200, width: 100,
                 height: 100, cluster: true)
    [source, target]
  end

  def thin_cluster_boxes
    source = box(width: 100, height: 4, cluster: true)
    target = box(x_coordinate: 149, y_coordinate: 5, width: 2, height: 2)
    [source, target]
  end

  def sample_centres
    positioned = box(x_coordinate: 10, y_coordinate: 20, width: 80, height: 40)
    [described_class.centre(positioned), described_class.centre({})]
  end

  describe ".cluster?" do
    it "recognizes only boxes explicitly marked as clusters" do
      values = [{ metadata: { cluster: true } },
                { metadata: { cluster: false } }, {}]

      expect(values.map { |value| described_class.cluster?(value) })
        .to eq([true, false, false])
    end
  end

  describe ".centre" do
    it "uses box coordinates and defaults missing dimensions" do
      expect(sample_centres).to eq([{ x: 50.0, y: 40.0 },
                                    { x: 50.0, y: 25.0 }])
    end
  end

  describe ".ends_of" do
    it "flattens the first and last points" do
      points = [{ x: 1, y: 2 }, { x: 3, y: 4 }, { x: 5, y: 6 }]

      expect(described_class.ends_of(points)).to eq([1, 2, 5, 6])
    end
  end

  describe "#route" do
    it "routes ordinary nodes from centre to centre" do
      points = [point(50.0, 25.0), point(250.0, 25.0)]

      expect_route(
        box,
        box(x_coordinate: 200),
        points: points,
        label_segment: [50.0, 25.0, 250.0, 25.0],
      )
    end

    it "trims cluster routes to their facing sides" do
      points = [point(100.0, 25.0), point(200.0, 25.0)]

      expect_route(
        box(cluster: true),
        box(x_coordinate: 200, cluster: true),
        points: points,
        label_segment: [100.0, 25.0, 200.0, 25.0],
      )
    end

    it "uses the internal detour segment for labels when clusters touch" do
      points = [point(0.0, 45.0), point(0, 70),
                point(200, 70), point(200.0, 45.0)]

      expect_route(
        box(cluster: true),
        box(x_coordinate: 100, cluster: true),
        points: points,
        label_segment: [0, 70, 200, 70],
      )
    end

    it "routes overlapping clusters outside both faces" do
      source, target = overlapping_cluster_boxes
      points = [point(0.0, 95.0), point(0, 145),
                point(175, 145), point(175.0, 120.0)]

      expect_route(
        source,
        target,
        points: points,
        label_segment: [0, 145, 175, 145],
      )
    end

    it "uses opposite sides when one cluster encloses the other" do
      source, target = nested_cluster_boxes
      points = [point(200.0, 200.0), point(50.0, 50.0)]

      expect_route(
        source,
        target,
        points: points,
        label_segment: [200.0, 200.0, 50.0, 50.0],
      )
    end

    it "draws a visible loop for coincident cluster centres" do
      points = [point(50.0, 0.0), point(120, 0),
                point(120, 50), point(50.0, 50.0)]

      expect_route(
        box(cluster: true),
        box(cluster: true),
        points: points,
        label_segment: [120, 0, 120, 50],
      )
    end

    it "uses supplied bends to choose the rounded source entry" do
      source, target = thin_cluster_boxes
      bends = [point(110.0, 4.0)]

      points, = router.route(source, target, bends)
      expect(points.first).to eq(x: 95.0, y: 4.0)
    end

    it "anchors diagonal routes on rounded cluster corners" do
      source, target = diagonal_cluster_boxes
      points = [point(98.54, 98.54), point(201.46, 201.46)]

      expect_route(
        source,
        target,
        points: points,
        label_segment: [98.54, 98.54, 201.46, 201.46],
      )
    end
  end
end
