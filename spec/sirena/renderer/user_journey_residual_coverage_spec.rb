# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/user_journey"

RSpec.describe Sirena::Renderer::UserJourney do
  subject(:renderer) { described_class.new }

  let(:label) do
    Sirena::Layout::UserJourney::Label.new(
      text: "Half", x: 10, y: 20, font_size: 14.5,
    )
  end
  let(:scene) do
    Sirena::Layout::UserJourney::Scene.new(
      width: 100, height: 100, view_box: "0 0 100 100", title: label,
    )
  end

  it "draws a low-score frown at the lower mouth offset" do
    task = { id: "low", metadata: { score: 2 } }
    xml = renderer.render({ id: "journey", children: [task] }).to_xml

    expect(xml).to include('d="M217.5,397A7.5,7.5')
  end

  it "preserves a fractional font size in rendered text" do
    expect(renderer.render(scene).to_xml).to include('font-size="14.5"')
  end
end
