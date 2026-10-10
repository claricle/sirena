# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart, "tall rounded nodes" do
  # A stadium is every point 18.5 from a spine; a tall one has a vertical spine.
  def spine_distance(x_value, y_value, half_spine)
    Math.hypot(x_value, y_value - y_value.clamp(-half_spine, half_spine))
  end

  it "rounds a tall node's corners by half its width" do
    xml = Sirena::Engine.new.render("flowchart TD\nD(x)\n")
    tag = xml[/<rect[^>]*\brx="[^"]*"[^>]*>/]

    expect(tag[/\swidth="([\d.]+)"/, 1].to_f).to be < tag[/\sheight="([\d.]+)"/, 1].to_f
    expect(tag[/\srx="([\d.]+)"/, 1].to_f)
      .to eq(tag[/\swidth="([\d.]+)"/, 1].to_f / 2)
  end

  [[10.0, 20.0], [-6.0, 30.0], [18.0, -4.0], [3.0, -40.0]].each do |x_diff, y_diff|
    it "ends a line from (#{x_diff}, #{y_diff}) on the stadium outline" do
      scale = described_class.new.send(:stadium_scale, 18.5, 25.5, x_diff, y_diff)

      expect(spine_distance(scale * x_diff, scale * y_diff, 7.0))
        .to be_within(1e-9).of(18.5)
    end
  end
end
