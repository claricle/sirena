# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Kanban, "#render" do
  let(:scene) do
    diagram = Sirena::Parser::Kanban.new.parse("kanban\n  todo\n    t1[task]\n")
    Sirena::Layout::Kanban.new.call(diagram)
  end
  let(:rects) { described_class.new.render(scene).children.grep(Sirena::Svg::Rect) }

  it "paints a card background that has a known style" do
    expect(rects.map(&:fill)).to all(be_a(String))
  end

  it "leaves a box with an unknown style unpainted" do
    scene.cards.first.background.style = "unknown"

    expect(rects.map(&:fill)).to include(nil)
  end
end
