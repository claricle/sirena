# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Pie, "#render" do
  subject(:renderer) { described_class.new(theme: theme) }

  let(:graph) do
    { slices: [{ label: "A", percentage: 100.0, angle: 360.0 }] }
  end
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) { Sirena::Layout::Pie.from_graph(graph, theme: theme) }
  let(:fill) do
    renderer.render(scene).children.grep(Sirena::Svg::Path).first.fill
  end

  it "paints the first slice from the theme's pie palette" do
    expect(fill).to eq(theme.colors.palette(:pie, 0))
  end

  it "uses a caller-defined pie palette" do
    renderer.theme = Sirena::Theme.new(
      colors: { pie_palette: ["#123456"] },
    )

    expect(fill).to eq("#123456")
  end
end
