# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "rexml/xpath"
require "sirena/renderer/user_journey"

RSpec.describe Sirena::Renderer::UserJourney do
  subject(:rendered_paint) do
    xml = described_class.new(theme: theme).render(graph).to_xml
    document = REXML::Document.new(xml)
    section_box = REXML::XPath.first(
      document, "//rect[contains(@class,'journey-section')]"
    )
    task_box = REXML::XPath.first(document, "//rect[contains(@class,'task')]")
    section_label = REXML::XPath.first(
      document, "//text[contains(@class,'journey-section')]"
    )
    task_label = REXML::XPath.first(document, "//text[@class='task']")
    task_line = REXML::XPath.first(document, "//line[@class='task-line']")
    face = REXML::XPath.first(document, "//circle[@class='face']")
    actor_dots = REXML::XPath.match(
      document, "//circle[starts-with(@class,'actor-')]"
    )
    eyes = REXML::XPath.match(document, "//circle[not(@class)]")
    mouth = REXML::XPath.first(document, "//path[@class='mouth']")
    timeline_line = REXML::XPath.first(document, "//line[not(@class)]")
    timeline_head = REXML::XPath.first(document, "//path[not(@class)]")

    {
      roles: {
        foreground_secondary: [section_box, task_box, task_line, *eyes, mouth]
          .map { |element| element.attributes["stroke"] },
        node_stroke: [face, *actor_dots]
          .map { |element| element.attributes["stroke"] },
        foreground: [*eyes, mouth]
          .map { |element| element.attributes["fill"] },
        edge_stroke: [timeline_line.attributes["stroke"],
                      timeline_head.attributes["fill"]],
      },
      categorical: [
        section_box, task_box, section_label, task_label, face, *actor_dots
      ]
        .map { |element| element.attributes["fill"] },
    }
  end

  let(:graph) do
    {
      id: "journey",
      children: [{
        id: "task_0", metadata: {
          name: "Browse products", score: 5, actors: ["Customer"],
          section_name: "Shopping"
        }
      }],
      metadata: { title: "My Journey", sections: ["Shopping"] },
    }
  end
  let(:expected_roles) do
    secondary = theme.colors.foreground_secondary
    secondary = "#666" if secondary == "#666666"
    {
      foreground_secondary: Array.new(6, secondary),
      node_stroke: Array.new(3, theme.colors.node_stroke),
      foreground: Array.new(3, theme.colors.foreground),
      edge_stroke: Array.new(2, theme.colors.edge_stroke),
    }
  end
  let(:expected_categorical) do
    [
      "#191970", "#191970", "#fff", "#fff", "#FFF8DC", "#8FBC8F",
      "#8FBC8F"
    ]
  end

  %i[default dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "themes neutral paint and preserves categorical fills" do
        expect(rendered_paint).to eq(
          roles: expected_roles, categorical: expected_categorical,
        )
      end
    end
  end

  context "with a neutral score" do
    let(:theme) { Sirena::Theme::Registry.get(:high_contrast) }
    let(:mouth_stroke) do
      graph[:children].first[:metadata][:score] = 3
      xml = described_class.new(theme: theme).render(graph).to_xml
      document = REXML::Document.new(xml)
      mouth = REXML::XPath.first(document, "//line[@class='mouth']")

      mouth.attributes["stroke"]
    end

    it "themes the flat mouth stroke" do
      expect(mouth_stroke).to eq(theme.colors.foreground_secondary)
    end
  end
end
