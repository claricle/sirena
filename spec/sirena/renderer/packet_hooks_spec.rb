# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Packet do
  subject(:renderer) { described_class.new }

  let(:source) { "packet-beta\n  title T\n  0-7: \"f\"\n" }
  let(:scene) do
    Sirena::Layout::Packet.new.call(Sirena::Parser::Packet.new.parse(source))
  end
  let(:svg) { renderer.render(scene) }

  def texts
    svg.children.grep(Sirena::Svg::Text).map { |t| Array(t.content).join }
  end

  it "writes the block label, both bit numbers, then the title" do
    expect(texts).to eq(%w[f 0 7 T])
  end

  it "writes no title when the diagram has none" do
    scene.title = nil

    expect(texts).to eq(%w[f 0 7])
  end

  it "draws no grid lines and no per-column bit markers" do
    expect(svg.children.grep(Sirena::Svg::Line)).to be_empty
  end

  it "fills blocks with mmdc's grey and black one-pixel stroke" do
    rect = svg.children.grep(Sirena::Svg::Rect).first

    expect([rect.fill, rect.stroke, rect.stroke_width])
      .to eq(["#efefef", "#000000", "1"])
  end
end
