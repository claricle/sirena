# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture, "#call junction circle" do
  let(:source) do
    <<~MERMAID
      architecture-beta
        service a(server)[A]
        junction j
        a:R -- L:j
    MERMAID
  end
  let(:scene) do
    described_class.new.call(
      Sirena::Parser::Architecture.new.parse(source),
    )
  end
  let(:junction) { scene.children.find { |node| node.kind == "junction" } }

  it "carries the circle centre and radius in the Scene" do
    expect([junction.center_x, junction.center_y, junction.radius]).to eq(
      [junction.x + (junction.width / 2), junction.y + (junction.height / 2),
       junction.width / 2],
    )
  end

  it "renders the circle from the Scene values" do
    junction.center_x = 123.0
    junction.center_y = 45.0
    junction.radius = 7.0
    xml = Sirena::Renderer::Architecture.new.render(scene).to_xml

    expect(xml).to include('cx="123.0"', 'cy="45.0"', 'r="7.0"')
  end
end
