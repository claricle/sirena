# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::FlowchartEdgeRouter do
  subject(:router) { described_class.new }

  def box(x: 0, y: 0, width: 100, height: 50, cluster: false)
    {
      x: x,
      y: y,
      width: width,
      height: height,
      metadata: { cluster: cluster }
    }
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
      expect([
        described_class.centre(box(x: 10, y: 20, width: 80, height: 40)),
        described_class.centre({}),
      ]).to eq([{ x: 50.0, y: 40.0 }, { x: 50.0, y: 25.0 }])
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
      source = box
      target = box(x: 200)

      expect(router.route(source, target)).to eq([
        [{ x: 50.0, y: 25.0 }, { x: 250.0, y: 25.0 }],
        [50.0, 25.0, 250.0, 25.0],
      ])
    end

    it "trims cluster routes to their facing sides" do
      source = box(cluster: true)
      target = box(x: 200, cluster: true)

      expect(router.route(source, target)).to eq([
        [{ x: 100.0, y: 25.0 }, { x: 200.0, y: 25.0 }],
        [100.0, 25.0, 200.0, 25.0],
      ])
    end

    it "uses the internal detour segment for labels when clusters touch" do
      source = box(cluster: true)
      target = box(x: 100, cluster: true)

      points, label_segment = router.route(source, target)

      expect([points, label_segment]).to eq([
        [{ x: 0.0, y: 45.0 }, { x: 0, y: 70 },
         { x: 200, y: 70 }, { x: 200.0, y: 45.0 }],
        [0, 70, 200, 70],
      ])
    end

    it "routes overlapping clusters outside both faces" do
      source = box(width: 100, height: 100, cluster: true)
      target = box(x: 75, y: 25, width: 100, height: 100, cluster: true)

      expect(router.route(source, target)).to eq([
        [{ x: 0.0, y: 95.0 }, { x: 0, y: 145 },
         { x: 175, y: 145 }, { x: 175.0, y: 120.0 }],
        [0, 145, 175, 145],
      ])
    end

    it "uses opposite sides when one cluster encloses the other" do
      source = box(width: 200, height: 200, cluster: true)
      target = box(x: 50, y: 50, width: 50, height: 50, cluster: true)

      expect(router.route(source, target)).to eq([
        [{ x: 200.0, y: 200.0 }, { x: 50.0, y: 50.0 }],
        [200.0, 200.0, 50.0, 50.0],
      ])
    end

    it "draws a visible loop for coincident cluster centres" do
      source = box(cluster: true)
      target = box(cluster: true)

      expect(router.route(source, target)).to eq([
        [{ x: 50.0, y: 0.0 }, { x: 120, y: 0 },
         { x: 120, y: 50 }, { x: 50.0, y: 50.0 }],
        [120, 0, 120, 50],
      ])
    end

    it "uses supplied bends to choose the rounded source entry" do
      source = box(width: 100, height: 4, cluster: true)
      target = box(x: 149, y: 5, width: 2, height: 2)
      bends = [{ x: 110.0, y: 4.0 }]

      points, = router.route(source, target, bends)

      expect(points.first).to eq(x: 95.0, y: 4.0)
    end

    it "anchors diagonal routes on rounded cluster corners" do
      source = box(width: 100, height: 100, cluster: true)
      target = box(x: 200, y: 200, width: 100, height: 100, cluster: true)

      expect(router.route(source, target)).to eq([
        [{ x: 98.54, y: 98.54 }, { x: 201.46, y: 201.46 }],
        [98.54, 98.54, 201.46, 201.46],
      ])
    end
  end
end
