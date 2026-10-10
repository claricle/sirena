# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Renderer do
  let(:scene) do
    scene_type = Sirena::Notation::PlantUML::Scene
    frames = [
      scene_type::Frame.new(
        id: "frame-basic", x: 10, y: 10, width: 80, height: 50,
        fill: nil, icon: false, texts: []
      ),
      scene_type::Frame.new(
        id: "frame-folder", x: 100, y: 10, width: 90, height: 60,
        tab_width: 40, fill: "#eeeeff", icon: true, texts: []
      ),
    ]
    markers = [
      scene_type::Marker.new(
        shape: "arrow", points: "180,100 170,95 170,105", filled: true,
      ),
      scene_type::Marker.new(
        shape: "nesting", cx: 20, cy: 100, r: 5,
        cross: "M 15 100 L 25 100 M 20 95 L 20 105"
      ),
    ]
    relation = scene_type::Relation.new(
      id: "relation-residual", path: "M 20 100 L 180 100",
      dashed: false, markers: markers, texts: []
    )
    boxes = [
      scene_type::Box.new(
        id: "note-default", x: 10, y: 120, width: 40, height: 20,
        kind: "note", fill: nil, separators: [], texts: []
      ),
      scene_type::Box.new(
        id: "note-hex", x: 60, y: 120, width: 40, height: 20,
        kind: "note", fill: "#abc", separators: [], texts: []
      ),
      scene_type::Box.new(
        id: "note-name", x: 110, y: 120, width: 40, height: 20,
        kind: "note", fill: "#yellow", separators: [], texts: []
      ),
      scene_type::Box.new(
        id: "plain", x: 160, y: 120, width: 40, height: 20,
        kind: "class", fill: nil, separators: [], texts: []
      ),
    ]

    scene_type.new(
      width: 220, height: 160, panels: [], frames: frames,
      relations: [relation], boxes: boxes
    )
  end

  let(:document) do
    REXML::Document.new(described_class.new.render(scene).to_xml)
  end

  let(:matches) { ->(xpath) { REXML::XPath.match(document, xpath) } }
  let(:note_fills) do
    %w[note-default note-hex note-name].to_h do |id|
      rect = matches.call("//g[@id='#{id}']/rect").first
      [id, rect.attributes["fill"]]
    end
  end
  let(:expected_note_fills) do
    {
      "note-default" => "#fbfb77", "note-hex" => "#abc",
      "note-name" => "yellow"
    }
  end

  it "draws optional frame tabs and package icons" do
    shapes = %w[frame-basic frame-folder].map do |id|
      group = matches.call("//g[@id='#{id}']").first
      [group.elements.to_a("rect").length, group.elements.to_a("circle").length]
    end

    expect(shapes).to eq([[1, 0], [2, 1]])
  end

  it "draws polygon and nesting relation markers" do
    marker_shapes = %w[polygon circle].to_h do |element|
      [element, matches.call("//g[@id='relation-residual']/#{element}").length]
    end

    expect(marker_shapes).to eq("polygon" => 1, "circle" => 1)
  end

  it "keeps note ids and resolves default, hex, and named fills" do
    expect(note_fills).to eq(expected_note_fills)
  end

  it "prefixes non-note box ids" do
    expect(matches.call("//g[@id='class-plain']").length).to eq(1)
  end
end
