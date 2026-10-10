# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart, ".from_graph" do
  # A stadium is every point 18.5 from a spine; a tall one has a vertical spine.
  def spine_distance(x_value, y_value, half_spine)
    Math.hypot(x_value, y_value - y_value.clamp(-half_spine, half_spine))
  end

  def corner_radius(shape, width, height)
    graph = { id: "g", edges: [],
              children: [{ id: "N", x: 0, y: 0, width: width, height: height,
                           metadata: { shape: shape } }] }

    described_class.from_graph(graph).children.first.corner_radius
  end

  # A stadium's ends are half its shorter side, whichever way it is long.
  [[100.0, 30.0], [30.0, 100.0]].each do |width, height|
    it "rounds a #{width.to_i}x#{height.to_i} stadium by half its shorter side" do
      expect(corner_radius("stadium", width, height)).to eq(15.0)
    end

    # mmdc draws `(x)` as a rect with rx 5, wide or tall.
    it "rounds a #{width.to_i}x#{height.to_i} `(x)` node by 5" do
      expect(corner_radius("rounded", width, height)).to eq(5.0)
    end
  end

  [%w[stadium 15.0], %w[rounded 5.0]].each do |shape, radius|
    it "draws a #{shape} node with rx #{radius}" do
      graph = { id: "g", edges: [],
                children: [{ id: "N", x: 0, y: 0, width: 30, height: 100,
                             metadata: { shape: shape } }] }
      scene = described_class.from_graph(graph)
      tag = Sirena::Renderer::Flowchart.new.render(scene).to_xml[/<rect[^>]*\brx="[^"]*"[^>]*>/]

      expect(tag[/\srx="([\d.]+)"/, 1].to_f).to eq(radius.to_f)
    end
  end

  [[10.0, 20.0], [-6.0, 30.0], [18.0, -4.0], [3.0, -40.0]].each do |x_diff, y_diff|
    it "ends a line from (#{x_diff}, #{y_diff}) on the stadium outline" do
      scale = described_class.new.send(:stadium_scale, 18.5, 25.5, x_diff, y_diff)

      expect(spine_distance(scale * x_diff, scale * y_diff, 7.0))
        .to be_within(1e-9).of(18.5)
    end
  end
end
