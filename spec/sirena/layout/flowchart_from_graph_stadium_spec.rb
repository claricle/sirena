# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart, ".from_graph" do
  let(:probe) { FlowchartShapeProbe }

  # A stadium's ends are half its shorter side, whichever way it is long.
  [[100.0, 30.0], [30.0, 100.0]].each do |width, height|
    it "rounds a #{width.to_i}x#{height.to_i} stadium by half its short side" do
      expect(probe.corner_radius("stadium", width, height)).to eq(15.0)
    end

    # mmdc draws `(x)` as a rect with rx 5, wide or tall.
    it "rounds a #{width.to_i}x#{height.to_i} `(x)` node by 5" do
      expect(probe.corner_radius("rounded", width, height)).to eq(5.0)
    end
  end

  [%w[stadium 15.0], %w[rounded 5.0]].each do |shape, radius|
    it "draws a #{shape} node with rx #{radius}" do
      expect(probe.rendered_rx(shape, 30, 100)).to eq(radius.to_f)
    end
  end

  [[10.0, 20.0], [-6.0, 30.0], [18.0, -4.0], [3.0, -40.0]].each do |dx, dy|
    it "ends a line from (#{dx}, #{dy}) on the stadium outline" do
      expect(probe.stadium_outline_distance(dx, dy)).to be_within(1e-9).of(18.5)
    end
  end
end
