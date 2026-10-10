# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/user_journey"

RSpec.describe Sirena::Renderer::UserJourney do
  let(:renderer) { described_class.new }

  describe "#render" do
    let(:dark) { Sirena::Theme::Registry.get(:dark) }
    let(:themed) { described_class.new(theme: dark).render(graph) }
    let(:theme_attributes) do
      [dark.typography.font_family, dark.colors.foreground]
    end
    let(:graph) do
      {
        id: "user_journey",
        children: [
          {
            id: "task_0",
            x: 100,
            y: 100,
            width: 150,
            height: 80,
            metadata: {
              name: "Browse products",
              score: 5,
              score_color: :green,
              actors: ["Customer"],
              section_name: "Shopping",
            },
          },
        ],
        edges: [],
        metadata: {
          title: "My Journey",
          sections: ["Shopping"],
        },
      }
    end

    it "renders graph to SVG document" do
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it "includes task boxes in SVG" do
      svg = renderer.render(graph)

      ids = svg.children.grep(Sirena::Svg::Group).map(&:id)

      expect(ids).to include("task-task_0")
    end

    it "renders task boxes as rectangles" do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      rects = groups.flat_map(&:children).grep(Sirena::Svg::Rect)

      expect(rects).not_to be_empty
    end

    it "fills a task box with its section colour" do
      svg = renderer.render(graph)

      rects = svg.children.grep(Sirena::Svg::Group).flat_map(&:children)
        .grep(Sirena::Svg::Rect)

      expect(rects.first.fill).to eq("#191970")
    end

    it "uses foreground colour and typography from the active theme" do
      expect(themed.to_xml).to include(*theme_attributes)
    end

    it "renders task content as text elements" do
      svg = renderer.render(graph)

      groups = svg.children.grep(Sirena::Svg::Group)

      texts = groups.flat_map(&:children).grep(Sirena::Svg::Text)

      expect(texts).not_to be_empty
    end

    it "renders title as text element" do
      svg = renderer.render(graph)

      texts = svg.children.grep(Sirena::Svg::Text)

      # `content` is `collection: true`, so read it through Array(...).
      title_text = texts.find { |t| Array(t.content).join == "My Journey" }
      expect(title_text).not_to be_nil
    end

    it "renders section headers as text elements" do
      svg = renderer.render(graph)

      texts = svg.children.grep(Sirena::Svg::Group).flat_map(&:children)
        .grep(Sirena::Svg::Text)

      section_text = texts.find { |t| Array(t.content).join == "Shopping" }
      expect(section_text).not_to be_nil
    end

    it "draws the timeline arrow" do
      svg = renderer.render(graph)

      expect(svg.children.last).to be_a(Sirena::Svg::Path)
    end
  end
end
