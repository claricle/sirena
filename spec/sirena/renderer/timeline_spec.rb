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
  let(:rendered_scene_evidence) do
    xml = document.to_xml
    entry = scene.tracks.first.entries.first
    snippets = [%(cx="#{entry.marker.x}"), %(cy="#{entry.marker.y}"),
                %(x="#{entry.labels.first.x}"), %(y="#{entry.labels.first.y}"),
                ">Shipped</text>"]

    [[document.width, document.height, document.view_box],
     snippets.map { |snippet| xml.include?(snippet) }]
  end

  it "renders the scene's final canvas and coordinates verbatim" do
    expected = [[scene.width, scene.height, scene.view_box], [true] * 5]

    expect(rendered_scene_evidence).to eq(expected)
  end

  it "does not retain positional state between renders" do
    renderer = described_class.new(theme: theme)
    first = renderer.render(scene).to_xml
    second = renderer.render(scene).to_xml

    expect(second).to eq(first)
  end
end
