# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Radar do
  subject(:renderer) { described_class.new }

  let(:source) do
    "radar-beta\n  title Skills\n  axis a, b, c\n  curve c1{1, 2, 3}\n"
  end
  let(:scene) do
    diagram = Sirena::Parser::Radar.new.parse(source)
    Sirena::Layout::Radar.new.call(diagram)
  end
  let(:title_text) do
    renderer.render(scene).children.grep(Sirena::Svg::Text)
      .find { |text| Array(text.content).join == "Skills" }
  end

  it "writes the font weight of a label that has one" do
    scene.title.font_weight = "bold"

    expect(title_text.font_weight).to eq("bold")
  end

  it "leaves the font weight unset for a label without one" do
    scene.title.font_weight = nil

    expect(title_text.font_weight).to be_nil
  end
end
