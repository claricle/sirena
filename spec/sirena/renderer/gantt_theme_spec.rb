# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/gantt"

RSpec.describe Sirena::Renderer::Gantt do
  subject(:svg) { described_class.new(theme: theme).render(scene) }

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) do
    label = Sirena::Layout::Gantt::Label
    rect = Sirena::Layout::Gantt::Rect
    task = Sirena::Layout::Gantt::Task
    tasks = %w[done active critical default].each_with_index.map do |status, i|
      task.new(
        label: label.new(text: status, x: 5, y: 75 + (i * 20), font_size: 12),
        bar: rect.new(
          x: 40, y: 65 + (i * 20), width: 30, height: 12,
          corner_radius: 2
        ),
        id_label: label.new(
          text: "#{status}-id", x: 45, y: 75 + (i * 20), font_size: 9,
        ),
        status: status,
      )
    end
    tasks << task.new(
      label: label.new(text: "milestone", x: 5, y: 155, font_size: 12),
      milestone_points: "80,145 90,155 80,165 70,155",
      status: "default",
    )
    section = Sirena::Layout::Gantt::Section.new(
      background: rect.new(x: 0, y: 55, width: 180, height: 120),
      label: label.new(text: "Section", x: 5, y: 60, font_size: 13),
      tasks: tasks,
    )
    timeline = Sirena::Layout::Gantt::Timeline.new(
      background: rect.new(x: 0, y: 25, width: 180, height: 25),
      labels: [label.new(text: "Tick", x: 20, y: 40, font_size: 10)],
      grid_lines: [
        Sirena::Layout::Gantt::Line.new(x1: 20, y1: 25, x2: 20, y2: 175),
      ],
    )
    Sirena::Layout::Gantt::Scene.new(
      width: 180, height: 180, view_box: "0 0 180 180",
      title: label.new(text: "Title", x: 5, y: 15, font_size: 16),
      timeline: timeline, sections: [section]
    )
  end
  let(:paint_summary) do
    texts = svg.children.grep(Sirena::Svg::Text).to_h do |text|
      [Array(text.content).join, [text.fill, text.font_family]]
    end
    {
      rect_fills: svg.children.grep(Sirena::Svg::Rect).map(&:fill),
      rect_strokes: svg.children.grep(Sirena::Svg::Rect).map(&:stroke),
      line_strokes: svg.children.grep(Sirena::Svg::Line).map(&:stroke),
      polygon_paint: svg.children.grep(Sirena::Svg::Polygon).map do |polygon|
        [polygon.fill, polygon.stroke]
      end,
      text_paint: texts,
    }
  end
  let(:expected_summary) do
    colors = theme.colors
    font = theme.typography&.font_family || "Arial, sans-serif"
    labels = %w[Title Tick Section done active critical default milestone]
      .to_h { |text| [text, [colors.label_text, font]] }
    ids = %w[done active critical default]
      .to_h { |status| ["#{status}-id", ["#ffffff", font]] }
    {
      rect_fills: [
        colors.node_fill, colors.section_bg, colors.success, colors.info,
        colors.error, colors.primary
      ],
      rect_strokes: [
        colors.node_stroke, "none", *Array.new(4, colors.node_stroke)
      ],
      line_strokes: [colors.node_stroke],
      polygon_paint: [[colors.primary, colors.node_stroke]],
      text_paint: labels.merge(ids),
    }
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses semantic roles for every task state and neutral mark" do
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

    it "leaves absent paint roles unset without legacy colours" do
      expect(paint_summary).to eq(expected_summary)
    end
  end
end
