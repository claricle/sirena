# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Timeline do
  subject(:layout) { described_class.new }

  def nonnumeric_entries
    named = Sirena::Diagram::TimelineEvent.new(
      time: "Now", descriptions: ["  shipped  "],
    )
    missing = Sirena::Diagram::TimelineEvent.new(
      time: nil, descriptions: ["Unknown"],
    )
    diagram = Sirena::Diagram::Timeline.new
    diagram.events.push(named, missing)
    layout.call(diagram).tracks.fetch(0).entries
  end

  def empty_section_scene
    diagram = Sirena::Diagram::Timeline.new
    diagram.sections << Sirena::Diagram::TimelineSection.new("Quiet")
    layout.call(diagram)
  end

  it "uses a titleless default track and range for an empty timeline" do
    scene = layout.call(Sirena::Diagram::Timeline.new)
    track = scene.tracks.fetch(0)

    expect([scene.width, scene.height, scene.title, track.entries,
            track.range_labels.map(&:text)])
      .to eq([960.0, 260.0, nil, [], %w[2000 2024 2012]])
  end

  it "places standalone nonnumeric and missing times at the track origin" do
    entries = nonnumeric_entries
    expect([entries.map { |entry| entry.marker.x },
            entries.map { |entry| entry.labels.map(&:text) }])
      .to eq([[80.0, 80.0], [["shipped", "Now"], ["Unknown", ""]]])
  end

  it "renders an empty section without manufacturing entries" do
    scene = empty_section_scene
    track = scene.tracks.fetch(0)

    expect([scene.height, track.header.text, track.header.section_index,
            track.entries, track.range_labels.map(&:text)])
      .to eq([320.0, "Quiet", 0, [], %w[2000 2024 2012]])
  end
end
