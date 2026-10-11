# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"
require "sirena/parser/mindmap"
require "sirena/layout/mindmap"
require "sirena/renderer/mindmap"

RSpec.describe Sirena::Layout::Mindmap do
  let(:source) do
    <<~MERMAID
      mindmap
        root[A root label<br/>second]
          child[A child label long enough to measure]
    MERMAID
  end
  let(:diagram) { Sirena::Parser::Mindmap.new.parse(source) }

  def scene_for(theme)
    described_class.new.call(diagram, theme: theme)
  end

  def partial_theme(font_size: nil, line_height: nil, font_family: nil)
    typography = Sirena::Theme::Typography.new(
      font_size_large: font_size, line_height: line_height,
      font_family: font_family
    )
    Sirena::Theme.new(
      colors: Sirena::Theme::ColorPalette.new, typography: typography,
    )
  end

  def label_summary(scene)
    scene.children.map do |node|
      label = node.labels.first
      [node.width, node.height, label.font_size,
       label.lines.map { |line| [line.text, line.x, line.y] }]
    end
  end

  def root_label(theme)
    scene_for(theme).children.first.labels.first
  end

  def final_line_evidence
    label = root_label(Sirena::Theme::Registry.get(:default))
    actual = label.lines.map { |line| [line.text, line.x, line.y] }
    expected = [["A root label ", label.x, label.y],
                ["second", label.x, (label.y + 19.2).round(4)]]
    [actual, expected]
  end

  def mutated_second_tspan
    scene = scene_for(Sirena::Theme::Registry.get(:default))
    mutate_last_line(scene)
    xml = Sirena::Renderer::Mindmap.new.render(scene).to_xml
    second_tspan(xml)
  end

  def mutate_last_line(scene)
    line = scene.children.first.labels.first.lines.last
    line.x = 123.25
    line.y = 456.75
  end

  def second_tspan(xml)
    REXML::XPath.match(REXML::Document.new(xml), "//tspan").fetch(1)
  end

  def node_metrics(scene)
    sizes = scene.children.map { |node| node.labels.first.font_size }.uniq
    [scene.children.first.height, sizes]
  end

  def custom_theme
    partial_theme(font_size: 20, line_height: 2, font_family: "Fira Sans")
  end

  def typography_evidence
    default = scene_for(Sirena::Theme::Registry.get(:default))
    contrast = scene_for(Sirena::Theme::Registry.get(:high_contrast))
    custom = scene_for(custom_theme)
    renderer = Sirena::Renderer::Mindmap.new(theme: custom_theme)
    xml = renderer.render(custom).to_xml
    [node_metrics(default), node_metrics(contrast), node_metrics(custom),
     xml.include?('font-family="Fira Sans" font-size="20.0"')]
  end

  def fallback_evidence
    default = label_summary(scene_for(Sirena::Theme::Registry.get(:default)))
    empty = label_summary(scene_for(partial_theme))
    invalid = label_summary(scene_for(partial_theme(font_size: 0,
                                                    line_height: -1)))
    [[empty, invalid], default]
  end

  it "preserves the representative default SVG exactly" do
    expect(Digest::SHA256.hexdigest(Sirena.render(source))).to eq(
      "9a77533cd6527bf23744e9a5d95c538605773137267688194c0f103f876d9e29",
    )
  end

  it "publishes every drawn line at its final baseline" do
    actual, expected = final_line_evidence

    expect(actual).to eq(expected)
  end

  it "copies mutated Scene line geometry without recalculating it" do
    second = mutated_second_tspan
    expect([second.attributes["x"], second.attributes["y"]])
      .to eq(["123.25", "456.75"])
  end

  it "uses built-in and custom font metrics coherently" do
    expect(typography_evidence).to eq(
      [[68.0, [16.0]], [77.6, [18.0]], [100.0, [20.0]], true],
    )
  end

  it "falls back from scalar-empty and invalid typography" do
    actual, expected = fallback_evidence

    expect(actual).to all(eq(expected))
  end
end
