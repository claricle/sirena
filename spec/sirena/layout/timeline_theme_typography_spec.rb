# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Timeline do
  let(:source) do
    <<~MERMAID
      timeline
        title Theme timeline
        section First section
        2024 : Machinery, Water power, Steam <br>power
    MERMAID
  end
  let(:themes) do
    {
      default: [16.0, 17.6],
      light: [16.0, 17.6],
      dark: [16.0, 17.6],
      high_contrast: [18.0, 19.8],
      { colors: { primary: "#123456" } } => [16.0, 17.6],
      { typography: { font_size_large: 20 } } => [20.0, 22.0],
    }
  end
  let(:rendered) do
    themes.keys.to_h { |theme| [theme, Sirena.render(source, theme: theme)] }
  end
  let(:heights) do
    rendered.transform_values { |svg| svg_height(svg) }
  end
  let(:geometry_summary) do
    partial = { colors: { primary: "#123456" } }
    custom = { typography: { font_size_large: 20 } }
    [rendered.values.all? { |svg| font_sizes(svg).include?(33.0) },
     heights[partial], heights[:default],
     heights[:high_contrast] > heights[:default],
     heights[custom] > heights[:high_contrast]]
  end

  def font_sizes(svg)
    svg.scan(/font-size="([0-9.]+)"/).flatten.map(&:to_f).uniq
  end

  def line_step(svg)
    rows = svg.scan(/<tspan[^>]* y="([0-9.]+)"/).flatten.map(&:to_f)
    (rows[1] - rows[0]).round(4)
  end

  def svg_height(svg)
    svg.match(/<svg[^>]* height="([0-9.]+)"/)[1].to_f
  end

  it "uses the large typography role for every timeline card" do
    actual = rendered.transform_values do |svg|
      [font_sizes(svg).min, line_step(svg)]
    end

    expect(actual).to eq(themes)
  end

  it "keeps the title fixed and grows the canvas with card typography" do
    expect(geometry_summary).to eq([true, 629.6, 629.6, true, true])
  end
end
