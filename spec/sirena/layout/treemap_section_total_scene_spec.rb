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
          "Clothing"
              "Shirts": 10
    MMD
  end
  let(:scene) do
    diagram = Sirena::Notation::Mermaid.parse(source).diagram
    described_class.new.call(diagram)
  end

  it "publishes final section totals in the scene" do
    electronics = scene.cells.first.children.first

    expect([scene.cells.first.total_label.text,
            electronics.total_label.text]).to eq(%w[90 80])
  end

  it "makes rendering independent of total derivation" do
    scene.cells.first.total_label.text = "scene-total"
    allow(Sirena::Renderer::Treemap::SectionTotal).to receive(:new)
      .and_raise("renderer derived section total")

    xml = Sirena::Renderer::Treemap.new.render(scene).to_xml

    expect(xml).to include(">scene-total</text>")
  end
end
