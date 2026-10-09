# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Timeline do
  let(:diagram) do
    Sirena::Parser::Timeline.new.parse(
      "timeline\n  title Release\n  2024 : Shipped\n",
    )
  end
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) { Sirena::Layout::Timeline.new.call(diagram, theme: theme) }
  let(:document) { described_class.new(theme: theme).render(scene) }

  it "renders the scene's final canvas and coordinates verbatim" do
    xml = document.to_xml
    entry = scene.tracks.first.entries.first

    expect([document.width, document.height, document.view_box]).to eq(
      [scene.width, scene.height, scene.view_box],
    )
    expect(xml).to include(
      %(cx="#{entry.marker.x}"), %(cy="#{entry.marker.y}"),
      %(x="#{entry.labels.first.x}"), %(y="#{entry.labels.first.y}"),
      ">Shipped</text>"
    )
  end

  it "does not retain positional state between renders" do
    renderer = described_class.new(theme: theme)
    first = renderer.render(scene).to_xml
    second = renderer.render(scene).to_xml

    expect(second).to eq(first)
  end
end
