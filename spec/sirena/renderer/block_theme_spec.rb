# frozen_string_literal: true

require "digest"
require "spec_helper"
require "sirena/renderer/block"

RSpec.describe Sirena::Renderer::Block do
  subject(:svg) { described_class.new(theme: theme).render(scene) }

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) do
    node = Sirena::Layout::Block::Node
    child = node.new(
      id: "child", x: 10, y: 10, width: 80, height: 40,
      labels: [], shape: "rectangle", compound: false, children: []
    )
    group = node.new(
      id: "group", x: 0, y: 0, width: 100, height: 60,
      labels: [], compound: true, children: [child]
    )
    Sirena::Layout::Block::Scene.new(
      width: 100, height: 60, view_box: "0 0 100 60",
      children: [group], edges: []
    )
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses the edge colour role for the compound border" do
        expect(compound_border.stroke).to eq(theme.colors.edge_color)
      end
    end
  end

  it "preserves the default SVG bytes" do
    expect(Digest::SHA256.hexdigest(svg.to_xml))
      .to eq("4c138f125944c660e4452f67bf71c77b131960cdbf3576bdf0da406af2dcd702")
  end

  context "with a scalar-empty partial theme" do
    let(:theme) do
      Sirena::Theme.new(colors: Sirena::Theme::ColorPalette.new)
    end

    it "leaves the compound border stroke unset" do
      expect(compound_border.stroke).to be_nil
    end
  end

  def compound_border
    svg.children.first.children.find do |element|
      element.is_a?(Sirena::Svg::Rect) && element.stroke_dasharray == "5,5"
    end
  end
end
