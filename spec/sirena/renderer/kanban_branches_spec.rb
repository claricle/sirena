# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Renderer::Kanban do
  subject(:xml) { renderer.render(layout).to_xml }

  let(:renderer) do
    described_class.new(theme: Sirena::Theme::Registry.get(:default))
  end
  let(:layout) do
    {
      columns: [column], cards: cards,
      width: 200, height: 150
    }
  end
  let(:column) do
    {
      id: "todo", title: "Todo", x: 0, y: 0,
      width: 200, height: 150, header_height: 50, card_count: cards.size
    }
  end
  let(:cards) { [] }

  def card(metadata: {}, has_metadata: false)
    {
      id: "work", text: "Work", column_id: "todo", x: 10, y: 60,
      width: 180, height: 80, metadata: metadata, has_metadata: has_metadata
    }
  end

  def parsed
    REXML::Document.new(xml)
  end

  def custom_theme
    colors = Struct.new(
      :background, :primary, :secondary, :border, :text
    ).new("#101010", "#202020", "#303030", nil, nil)
    typography = Struct.new(:font_size, :font_family).new(17, "Test Sans")
    Struct.new(:colors, :typography).new(colors, typography)
  end

  describe "rendering branches" do
    it "omits the card-count badge for an empty column" do
      badge_rects = REXML::XPath.match(parsed, "//rect[@width='20.0']")

      expect(badge_rects).to be_empty
    end

    it "renders the card-count badge for a nonempty column" do
      cards << card
      badge = REXML::XPath.first(parsed, "//text[.='1']")

      expect(badge).to have_attributes(text: "1")
    end

    it "suppresses nil and empty metadata values while formatting a key" do
      cards << card(
        metadata: { assigned: nil, ticket: "", story_points: 5 },
        has_metadata: true,
      )
      texts = REXML::XPath.match(parsed, "//text").filter_map(&:text)
      metadata_texts = texts.grep(/Assigned|Ticket|Story_points|\A5\z/)

      expect(metadata_texts).to eq(["Story_points:", "5"])
    end

    it "uses theme colors and typography where the theme defines them" do
      cards << card(metadata: { assigned: "Alice" }, has_metadata: true)
      themed_renderer = described_class.new(theme: custom_theme)
      themed_xml = themed_renderer.render(layout).to_xml

      expect(themed_xml).to include(
        'fill="#101010"', 'fill="#202020"', 'fill="#303030"',
        'font-size="17"', 'font-family="Test Sans"'
      )
    end

    it "uses fallback styles when the theme omits them" do
      cards << card
      fallback = described_class.new(theme: Sirena::Theme.new).render(layout).to_xml

      expect(fallback).to include(
        'fill="#f3f4f6"', 'stroke="#d1d5db"',
        'fill="#3b82f6"', 'fill="#1f2937"',
        'font-family="Arial, sans-serif"'
      )
    end

    it "adds forty pixels of document padding and offsets board geometry" do
      document = parsed.root
      background = REXML::XPath.first(parsed, "//rect")

      expect([document.attributes["width"], document.attributes["height"],
              background.attributes["x"], background.attributes["y"]])
        .to eq(%w[280.0 230.0 40.0 40.0])
    end
  end
end
