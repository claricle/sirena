# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Renderer do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:document) do
    REXML::Document.new(
      Sirena.render(class_source, notation: :plantuml, theme: theme),
    )
  end

  def class_source
    <<~PLANTUML
      @startuml
      class A {
      +x : int
      }
      class B
      A --> B : uses
      @enduml
    PLANTUML
  end

  def attributes(path, *names)
    REXML::XPath.match(document, path).map do |element|
      names.map { |name| element.attributes[name] }
    end
  end

  def paint_summary
    {
      boxes: attributes(
        "//g[starts-with(@id, 'class-')]/rect", "fill", "stroke"
      ),
      separators: attributes("//g[starts-with(@id, 'class-')]/line", "stroke"),
      relation_paths: attributes(
        "//g[starts-with(@id, 'relation-')]/path", "stroke"
      ),
      relation_markers: attributes(
        "//g[starts-with(@id, 'relation-')]/polygon", "fill", "stroke"
      ),
      text: attributes("//text", "fill"),
    }
  end

  # PlantUML draws its own look, whatever Mermaid theme is passed.
  def expected_paints
    {
      boxes: Array.new(2, %w[#F1F1F1 #181818]),
      separators: Array.new(4, %w[#181818]),
      relation_paths: [%w[#181818]],
      relation_markers: [%w[#181818 #181818]],
      text: Array.new(4, %w[#000000]),
    }
  end

  def partial_render_summary
    {
      paints: paint_summary,
      font_families: attributes("//text", "font-family").flatten.uniq,
      box_widths: attributes(
        "//g[starts-with(@id, 'class-')]/rect", "stroke-width"
      ).flatten,
      relation_widths: attributes(
        "//g[starts-with(@id, 'relation-')]/*[self::path or self::polygon]",
        "stroke-width",
      ).flatten,
    }
  end

  def expected_partial_summary
    {
      paints: expected_paints,
      font_families: %w[sans-serif],
      box_widths: %w[0.5 0.5],
      relation_widths: %w[1 1],
    }
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "draws PlantUML's own class paints, not the theme's" do
        expect(paint_summary).to eq(expected_paints)
      end
    end
  end

  it "preserves the representative default SVG" do
    svg = Sirena.render(class_source, notation: :plantuml, theme: theme)

    expect(Digest::SHA256.hexdigest(svg)).to eq(
      "29a773eb1af2bc0e242b03dc48427075b527a53a1a195951b66afd17d82f3a65",
    )
  end

  context "with a scalar-empty partial theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new,
        typography: Sirena::Theme::Typography.new,
        shapes: Sirena::Theme::ShapeStyles.new,
      )
    end

    it "leaves semantic paints unset while retaining non-paint fallbacks" do
      expect(partial_render_summary).to eq(expected_partial_summary)
    end
  end
end
