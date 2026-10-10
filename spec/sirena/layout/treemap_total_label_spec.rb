# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe Sirena::Layout::Treemap do
  let(:source) do
    <<~MMD
      treemap-beta
      "Products"
          "Electronics"
              "Phones": 50
              "Computers": 30
    MMD
  end
  let(:scene) do
    described_class.new.call(
      Sirena::Notation::Mermaid.parse(source).diagram,
    )
  end
  let(:section) { scene.cells.first }
  let(:svg) { Sirena::Engine.new.render(source) }

  it "anchors the section total at the right edge of the cell" do
    expect(section.total_label.x).to eq(section.box.x + section.box.width - 5)
  end

  it "aligns the section total with the section label" do
    expect(section.total_label.y).to eq(section.label.y)
  end

  it "gives leaves no total label" do
    leaf = section.children.first.children.first
    expect(leaf.total_label).to be_nil
  end

  it "renders the total at the scene anchor, end-aligned" do
    x = section.total_label.x.to_f
    y = section.total_label.y.to_f
    expect(svg).to match(
      %r{<text[^>]*x="#{x}"[^>]*y="#{y}"[^>]*text-anchor="end"[^>]*>80</text>},
    )
  end
end
