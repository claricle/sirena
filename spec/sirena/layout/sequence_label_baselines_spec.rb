# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:scene) { layout_scene("A->>B: one<br>two<br>three") }
  let(:label) { scene.messages.first.label }
  let(:svg) { Sirena::Renderer::Sequence.new.render(scene).to_xml }

  def tspan_ys(markup)
    markup.scan(/<tspan[^>]* y="([^"]+)"/).flatten.map(&:to_f)
  end

  it "publishes one final baseline per drawn line" do
    expect(label.line_ys).to eq([0, 1, 2].map { |row| label.y + (row * 19) })
  end

  it "has no baselines for a one-line message" do
    expect(layout_scene("A->>B: one").messages.first.label.line_ys).to eq([])
  end

  it "serializes the published baselines without computing any" do
    label.line_ys = [11.0, 222.0, 3333.0]

    expect(tspan_ys(svg)).to eq([11.0, 222.0, 3333.0])
  end

  it "renders the layout's own baselines as the line positions" do
    expect(tspan_ys(svg)).to eq(label.line_ys)
  end
end
