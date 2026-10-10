# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Packet, "protected hooks" do
  subject(:renderer) { described_class.new }

  let(:svg) { Sirena::Svg::Document.new }
  let(:layout) { { title: "T", width: 400, padding: 10, title_height: 20 } }

  def hook(name, *arguments)
    renderer.send(name, *arguments)
  end

  def texts
    svg.children.grep(Sirena::Svg::Text).map { |t| Array(t.content).join }
  end

  def field(width)
    { label: "f", bit_start: 0, bit_end: 7, x: 0, y: 0,
      width: width, height: 20 }
  end

  it "writes the title when the layout has one" do
    hook(:render_title, layout, svg)

    expect(texts).to eq(["T"])
  end

  it "writes no title when the layout has none" do
    hook(:render_title, layout.merge(title: nil), svg)

    expect(texts).to be_empty
  end

  it "adds a bit range to a wide field" do
    renderer.instance_variable_set(:@title_offset, 0)
    hook(:render_field, field(200), {}, svg)

    expect(texts).to eq(%w[f 0-7])
  end

  it "leaves the bit range off a narrow field" do
    renderer.instance_variable_set(:@title_offset, 0)
    hook(:render_field, field(100), {}, svg)

    expect(texts).to eq(%w[f])
  end
end
