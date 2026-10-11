# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

module ArchitectureThemeTypographySpecHelpers
  ATTRIBUTES = %w[font-size font-family font-weight text-anchor].freeze
  DEFAULT_DIGEST =
    "ce20efa613666c81c2714ae8f343a02a" \
    "283c8c3ee2bb82c34d923cc1c62fa1ba"
  SOURCE = <<~MERMAID
    architecture-beta
      group api(cloud)[API]
      service a(server)[Service] in api
      service b(database)[Peer] in api
      a:R -- L:b : HTTP
  MERMAID

  module_function

  def render(theme)
    diagram = Sirena::Parser::Architecture.new.parse(SOURCE)
    scene = Sirena::Layout::Architecture.new.call(diagram, theme: theme)
    svg = Sirena::Renderer::Architecture.new(theme: theme).render(scene)
    [scene, svg]
  end

  def scene_typography(scene)
    scene_labels(scene).map do |label|
      [label.font_size, label.font_weight, label.text_anchor,
       label.respond_to?(:font_family)]
    end
  end

  def scene_labels(scene)
    labels = scene.children.flat_map(&:labels)
      .to_h { |label| [label.text, label] }
    [labels.fetch("API"),
     labels.fetch("Service"),
     scene.edges.first.labels.first]
  end

  def svg_typography(svg)
    document = REXML::Document.new(svg.to_xml)
    %w[API Service HTTP].map do |content|
      text = REXML::XPath.first(
        document, "//*[local-name()='text' and text()='#{content}']"
      )
      ATTRIBUTES.map do |attribute|
        text.attributes[attribute]
      end
    end
  end

  def typography(theme)
    scene, svg = render(theme)
    [scene_typography(scene), svg_typography(svg)]
  end

  def default_result
    scene, svg = render(Sirena::Theme::Registry.get(:default))
    [scene_typography(scene), Digest::SHA256.hexdigest(svg.to_xml)]
  end

  def default_expected
    [[[14, "bold", nil, false],
      [12, nil, "middle", false],
      [10, nil, "middle", false]], DEFAULT_DIGEST]
  end

  def high_contrast_expected
    scene = [[16.8, "bold", nil, false],
             [96.0 / 7, nil, "middle", false],
             [35.0 / 3, nil, "middle", false]]
    svg = [["16.8", nil, "bold", nil],
           [(96.0 / 7).to_s, "Arial, Helvetica, sans-serif", nil, "middle"],
           [(35.0 / 3).to_s, nil, nil, "middle"]]
    [scene, svg]
  end

  def custom_theme
    typography = Sirena::Theme::Typography.new(
      font_family: "Example Sans", font_size_title: 30,
      font_size_normal: 21, font_size_small: 18, font_weight_bold: "700"
    )
    Sirena::Theme.new(typography: typography)
  end

  def custom_expected
    [[[21, "700", nil, false],
      [18, nil, "middle", false],
      [15, nil, "middle", false]],
     [["21", nil, "700", nil],
      ["18", "Example Sans", nil, "middle"],
      ["15", nil, nil, "middle"]]]
  end

  def empty_theme
    Sirena::Theme.new(typography: Sirena::Theme::Typography.new)
  end

  def empty_expected
    [default_expected.first,
     [["14", nil, "bold", nil],
      ["12", "Arial, Helvetica, sans-serif", nil, "middle"],
      ["10", nil, nil, "middle"]]]
  end

  def mutation_result
    scene, = render(Sirena::Theme::Registry.get(:default))
    before = scene_typography(scene)
    mutate(scene_labels(scene))
    svg = Sirena::Renderer::Architecture.new.render(scene)
    [*before, svg_typography(svg)]
  end

  def mutate(labels)
    labels.zip([31, 32, 33]).each { |label, size| label.font_size = size }
    labels[0].font_weight = "900"
    labels[2].text_anchor = "end"
  end

  def mutation_expected
    [[14, "bold", nil, false],
     [12, nil, "middle", false],
     [10, nil, "middle", false],
     [["31", nil, "900", nil],
      ["32", "Arial, Helvetica, sans-serif", nil, "middle"],
      ["33", nil, nil, "end"]]]
  end
end

RSpec.describe Sirena::Layout::Architecture do
  let(:helpers) { ArchitectureThemeTypographySpecHelpers }

  it "publishes exact default label typography without changing SVG bytes" do
    expect(helpers.default_result).to eq(helpers.default_expected)
  end

  it "derives high-contrast Scene and SVG values from typography roles" do
    theme = Sirena::Theme::Registry.get(:high_contrast)
    expect(helpers.typography(theme)).to eq(helpers.high_contrast_expected)
  end

  it "derives custom Scene and SVG values from typography roles" do
    expect(helpers.typography(helpers.custom_theme))
      .to eq(helpers.custom_expected)
  end

  it "keeps family out of Scene and falls back for empty typography" do
    expect(helpers.typography(helpers.empty_theme))
      .to eq(helpers.empty_expected)
  end

  it "serializes mutated Scene typography without renderer inference" do
    expect(helpers.mutation_result).to eq(helpers.mutation_expected)
  end
end
