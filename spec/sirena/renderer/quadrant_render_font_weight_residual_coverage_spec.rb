# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Quadrant, "#render" do
  subject(:rendered_title) do
    group = described_class.new.render(scene).children
      .grep(Sirena::Svg::Group).find { |item| item.class_name == "title" }
    group.children.grep(Sirena::Svg::Text).first
  end

  let(:scene) do
    diagram = Sirena::Parser::Quadrant.new.parse("quadrantChart\n  title T\n")
    Sirena::Layout::Quadrant.new.call(diagram)
  end

  it "serializes typed Scene label emphasis" do
    scene.title.font_weight = "bold"

    expect(rendered_title.font_weight).to eq("bold")
  end
end
