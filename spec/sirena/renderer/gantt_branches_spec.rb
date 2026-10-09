# frozen_string_literal: true

require "spec_helper"
require "date"

RSpec.describe Sirena::Renderer::Gantt do
  subject(:renderer) { described_class.new }

  let(:layout) { Sirena::Layout::Gantt.new }

  def label(text)
    Sirena::Layout::Gantt::Label.new(
      text: text, x: 10, y: 10, font_size: 12,
    )
  end

  def background(kind)
    Sirena::Layout::Gantt::Rect.new(
      x: 0, y: 0, width: 100, height: 20, kind: kind,
    )
  end

  def scene(title: nil, timeline: nil, sections: [])
    Sirena::Layout::Gantt::Scene.new(
      width: 200, height: 100, view_box: "0 0 200 100",
      title: title, timeline: timeline, sections: sections
    )
  end

  def xml_for(scene)
    renderer.render(scene).to_xml
  end

  def date_labels(format)
    layout.send(
      :date_labels,
      { total_days: 10, start_date: Date.new(2024, 1, 1) },
      format,
    )
  end

  let(:plain_section) do
    task = Sirena::Layout::Gantt::Task.new(
      label: label("d"), status: "default",
    )
    Sirena::Layout::Gantt::Section.new(
      background: background("section"), label: label("S"), tasks: [task],
    )
  end

  let(:empty_timeline) do
    Sirena::Layout::Gantt::Timeline.new(
      background: background("timeline"), labels: [], grid_lines: [],
    )
  end

  let(:bar_tasks) do
    %w[critical done active default].map do |status|
      Sirena::Layout::Gantt::Task.new(
        label: label(status), status: status,
        bar: Sirena::Layout::Gantt::Rect.new(
          x: 10, y: 10, width: 50, height: 24, corner_radius: 3, kind: "task",
        ),
      )
    end
  end

  let(:coloured_section) do
    tasks = bar_tasks + [
      Sirena::Layout::Gantt::Task.new(
        label: label("none"), status: "default",
      ),
    ]
    Sirena::Layout::Gantt::Section.new(
      background: background("section"), label: label("S"), tasks: tasks,
    )
  end

  it "draws no timeline axis when the Scene has no timeline" do
    xml = xml_for(scene(title: label("T"), sections: [plain_section]))
    text_present = %w[T S d].all? { |text| xml.include?(">#{text}<") }
    expect([xml.scan("<text").size, text_present]).to eq([3, true])
  end

  it "draws no date labels for a zero-day timeline" do
    expect(xml_for(scene(timeline: empty_timeline))).not_to include("<text")
  end

  it "lays out a 10-day timeline every 7 days in month-day form" do
    expect(date_labels(nil).map(&:text)).to eq(%w[01-01 01-08])
  end

  it "applies the graph axis format while laying out date labels" do
    expect(date_labels("%d/%m").map(&:text)).to eq(%w[01/01 08/01])
  end

  it "colours bars by status and draws no bar without geometry" do
    xml = xml_for(scene(sections: [coloured_section]))
    counts = described_class::TASK_COLORS.values.map do |colour|
      xml.scan(%(fill="#{colour}")).size
    end
    expect(counts).to eq([1, 1, 1, 1])
  end
end
