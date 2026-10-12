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

  def expected_paints(colors)
    {
      boxes: Array.new(2, [colors.node_fill, colors.node_stroke]),
      separators: [[colors.node_stroke]],
      relation_paths: [[colors.edge_stroke]],
      relation_markers: [[colors.edge_stroke, colors.edge_stroke]],
      text: Array.new(4, [colors.label_text]),
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
      paints: expected_paints(theme.colors),
      font_families: ["Arial, sans-serif", "monospace"],
      box_widths: %w[2 2],
      relation_widths: %w[2 2],
    }
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses its semantic class paint roles" do
        expect(paint_summary).to eq(expected_paints(theme.colors))
      end
    end
  end

  it "preserves the representative default SVG" do
    svg = Sirena.render(class_source, notation: :plantuml, theme: theme)

    expect(Digest::SHA256.hexdigest(svg)).to eq(
      "cb6a355b7e7eae97628cc7b04cd79c8ef6cbd37f42153d9a3f0327c130b22efc",
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
