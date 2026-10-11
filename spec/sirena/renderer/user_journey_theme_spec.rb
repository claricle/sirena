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
    section = theme.colors.user_journey_section_palette.first
    actor = theme.colors.user_journey_actor_palette.first
    [
      section, section, "#fff", "#fff", "#FFF8DC", actor, actor
    ]
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "themes neutral paint and preserves categorical fills" do
        expect(rendered_paint).to eq(
          roles: expected_roles, categorical: expected_categorical,
        )
      end
    end
  end

  context "with every dark categorical colour" do
    let(:theme) { Sirena::Theme::Registry.get(:dark) }
    let(:actors) { 6.times.map { |index| "actor #{index}" } }
    let(:palette_graph) do
      children = 7.times.map do |index|
        {
          id: "task_#{index}", metadata: {
            name: "task #{index}", score: 5,
            actors: index.zero? ? actors : [],
            section_name: "section #{index}"
          }
        }
      end
      { id: "journey", children: children, metadata: {} }
    end
    let(:palette_scene) do
      Sirena::Layout::UserJourney.from_graph(palette_graph, theme: theme)
    end

    it "uses every dark section and actor palette entry in order" do
      sections = palette_scene.sections.map { |section| section.box.fill }
      tasks = palette_scene.tasks.map { |task| task.box.fill }
      actor_fills = palette_scene.legend.map { |actor| actor.dot.colour }

      expect([sections, tasks, actor_fills]).to eq(
        [theme.colors.user_journey_section_palette,
         theme.colors.user_journey_section_palette,
         theme.colors.user_journey_actor_palette],
      )
    end

    it "keeps every section fill legible under its white labels" do
      pairs = palette_scene.sections.map do |section|
        [section.box.fill, section.labels.first.fill]
      end
      pairs.concat(palette_scene.tasks.map do |task|
        [task.box.fill, task.labels.first.fill]
      end)

      expect(pairs.map { |fill, label| contrast(fill, label) })
        .to all(be >= 4.5)
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

  def contrast(left, right)
    high, low = [luminance(left), luminance(right)].sort.reverse
    (high + 0.05) / (low + 0.05)
  end

  def luminance(hex)
    value = hex.delete_prefix("#")
    if value.length == 3
      value = value.chars.map { |character| character * 2 }.join
    end
    channels = value.scan(/../).map do |pair|
      channel = pair.to_i(16) / 255.0
      if channel <= 0.04045
        channel / 12.92
      else
        ((channel + 0.055) / 1.055)**2.4
      end
    end
    channels.zip([0.2126, 0.7152, 0.0722])
      .sum { |channel, weight| channel * weight }
  end
end
