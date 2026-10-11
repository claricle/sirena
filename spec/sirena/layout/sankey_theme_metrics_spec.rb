# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::Sankey do
  let(:source) { File.read("examples/sankey/01-simple-flow.mmd") }
  let(:diagram) do
    Sirena::Parser::Sankey.new.parse(source).tap do |item|
      item.title = "Energy Flow"
    end
  end

  def theme(large:, small:)
    Sirena::Theme.new(
      typography: Sirena::Theme::Typography.new(
        font_size_large: large, font_size_small: small,
      ),
    )
  end

  def scene_for(value)
    described_class.new.call(diagram, theme: value)
  end

  def metric_summary(value)
    scene = scene_for(value)
    [scene.title.font_size, *node_metrics(scene.nodes.first),
     *flow_metrics(scene.flows.first)]
  end

  def node_metrics(node)
    [node.height, node.label.font_size, node.label.y]
  end

  def flow_metrics(flow)
    [flow.label.font_size, flow.label.y]
  end

  def themed_metrics
    themes = [Sirena::Theme::Registry.get(:default),
              Sirena::Theme::Registry.get(:high_contrast),
              theme(large: 24, small: 18)]
    themes.map { |value| metric_summary(value) }
  end

  def expected_themed_metrics
    [[16.0, 40.0, 12.0, 125.0, 12.0, 120.0],
     [18.0, 46.6667, 14.0, 129.1667, 14.0, 123.3334],
     [24.0, 60.0, 18.0, 137.5, 18.0, 130.0]]
  end

  def fallback_metrics
    [theme(large: nil, small: nil), theme(large: 0, small: -1)]
      .map { |value| metric_summary(value) }
  end

  it "preserves the representative registered-default SVG exactly" do
    expect(Digest::SHA256.hexdigest(Sirena.render(source))).to eq(
      "0df7e2b4e53e22019e9a6b87e9cd65dc920c32a6e8f4eeda99312e44da54a8e6",
    )
  end

  it "uses built-in and custom font metrics for final Scene geometry" do
    expect(themed_metrics).to eq(expected_themed_metrics)
  end

  it "retains the renderer fallbacks for scalar-empty typography" do
    expected = [18.0, 36.6667, 11.0, 122.9167, 10.0, 118.3334]

    expect(fallback_metrics).to all(eq(expected))
  end

  it "serializes resolved font sizes with the final Scene labels" do
    scene = scene_for(Sirena::Theme::Registry.get(:high_contrast))
    labels = [scene.title, scene.nodes.first.label, scene.flows.first.label]

    expect(labels.map { |label| label.to_hash["font_size"] })
      .to eq([18.0, 14.0, 14.0])
  end

  it "renders a mutated final label baseline without recalculating it" do
    scene = scene_for(Sirena::Theme::Registry.get(:default))
    scene.nodes.first.label.y = 456.25
    xml = Sirena::Renderer::Sankey.new.render(scene).to_xml

    expect(xml).to match(/y="456\.25"[^>]*>Engineering<\/text>/)
  end
end
