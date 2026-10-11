# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Renderer::Kanban do
  let(:source) { File.read("examples/kanban/01-simple-board.mmd") }
  let(:document) { REXML::Document.new(Sirena.render(source, theme: theme)) }
  let(:paint_summary) do
    rectangles = REXML::XPath.match(document, "//rect")
    text_colours = REXML::XPath.match(document, "//text").to_h do |element|
      content = REXML::XPath.match(element, ".//text()").map(&:value).join
      [content, element.attributes["fill"]]
    end

    {
      headers: rectangles.select { |rect| rect.attributes["height"] == "25.0" }
        .map { |rect| rect.attributes["fill"] },
      badges: rectangles.select { |rect| rect.attributes["rx"] == "10.0" }
        .map { |rect| rect.attributes["fill"] },
      cards: rectangles.select { |rect| rect.attributes["rx"] == "6.0" }
        .map { |rect| rect.attributes["fill"] },
      text: text_colours.slice("Todo", "2", "Create Documentation",
                               "Ticket:", "DOC-001"),
    }
  end
  let(:expected_summary) do
    colors = theme.colors
    {
      headers: Array.new(3, colors.primary),
      badges: Array.new(3, colors.foreground),
      cards: Array.new(4, colors.node_fill),
      text: {
        "Todo" => colors.background,
        "2" => colors.background,
        "Create Documentation" => colors.label_text,
        "Ticket:" => colors.secondary,
        "DOC-001" => colors.label_text,
      },
    }
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses semantic paint roles for the board" do
        expect(paint_summary).to eq(expected_summary)
      end
    end
  end

  context "with a partial theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new(primary: "#123abc"),
      )
    end

    it "leaves omitted scalar roles unpainted" do
      expect(paint_summary).to eq(expected_summary)
    end
  end
end
