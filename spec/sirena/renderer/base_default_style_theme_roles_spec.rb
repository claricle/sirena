# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Base, "#default_style theme roles" do
  let(:renderer_class) do
    Class.new(described_class) do
      public :default_style
    end
  end

  def paint_values(renderer)
    node = renderer.default_style(:node)
    edge = renderer.default_style(:edge)
    text = renderer.default_style(:text)

    [node.fill, node.stroke, edge.stroke, text.fill]
  end

  def theme_paint(theme)
    colors = theme.colors
    [colors.node_fill, colors.node_stroke, colors.edge_stroke,
     colors.label_text]
  end

  it "preserves the built-in default paint" do
    renderer = renderer_class.new(theme: Sirena::Theme::Registry.get(:default))
    expect(paint_values(renderer))
      .to eq(["#ffffff", "#000000", "#000000", "#000000"])
  end

  it "takes every paint value from the dark theme" do
    dark = Sirena::Theme::Registry.get(:dark)
    expect(paint_values(renderer_class.new(theme: dark)))
      .to eq(theme_paint(dark))
  end

  it "omits paint roles absent from a scalar-empty theme" do
    empty_theme = Sirena::Theme.new(colors: Sirena::Theme::ColorPalette.new)
    expect(paint_values(renderer_class.new(theme: empty_theme)))
      .to eq([nil, nil, nil, nil])
  end
end
