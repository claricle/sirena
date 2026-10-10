# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Svg do
  it "ignores a path command whose type is unsupported" do
    command = { type: :unsupported, x: 1, y: 2 }

    expect(Sirena::Svg::Path.build_path_data([command])).to eq("")
  end

  it "omits a multiline y coordinate when placement is non-finite" do
    run = Sirena::Svg::Tspan.new.tap do |tspan|
      tspan.content = "line"
      tspan.line_shift = 1
    end
    text = Sirena::Svg::Text.new.tap do |element|
      element.y = 10
      element.font_size = "1e400"
      element.tspans = [run]
    end

    expect(text.to_xml)
      .to eq('<text y="10.0" font-size="1e400"><tspan>line</tspan></text>')
  end
end
