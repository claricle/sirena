# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Renderer do
  let(:scene) do
    scene_type = Sirena::Notation::PlantUML::Sequence::Scene
    text_type = Sirena::Notation::PlantUML::Scene::Text
    segment_type = Sirena::Notation::PlantUML::Scene::Segment
    line = segment_type.new(x1: 10, y1: 100, x2: 190, y2: 100)
    arrow = scene_type::Arrow.new(
      id: "arrow-residual", path: "M 20 30 L 180 30", dashed: true,
      colour: "#123456", texts: [], marks: [
        scene_type::Mark.new(
          kind: "polygon", filled: false, points: "180,30 170,25 170,35",
        ),
        scene_type::Mark.new(kind: "circle", cx: 20, cy: 30, r: 4),
        scene_type::Mark.new(
          kind: "line", heavy: true, x1: 20, y1: 25, x2: 20, y2: 35,
        ),
        scene_type::Mark.new(
          kind: "line", heavy: false, x1: 24, y1: 25, x2: 24, y2: 35,
        ),
      ]
    )
    notes = [
      scene_type::Note.new(
        path: "M 20 50 L 80 50 L 80 80 L 20 80 Z",
        fill: "#abcdef", texts: []
      ),
      scene_type::Note.new(
        path: "M 90 50 L 150 50 L 150 80 L 90 80 Z",
        fill: "#abcdef", fill_opacity: 0.5, texts: []
      ),
    ]
    dividers = [
      scene_type::Divider.new(
        lines: [line], x: 60, y: 100, width: 80, height: 18, texts: [],
      ),
      scene_type::Divider.new(
        lines: [line], x: 60, y: 120, width: 80, height: 18,
        texts: [text_type.new(content: "label", x: 100, y: 133)]
      ),
    ]
    heads = [
      scene_type::Head.new(
        id: "A", kind: "participant", x: 20, y: 150,
        width: 80, height: 30, texts: []
      ),
      scene_type::Head.new(
        id: "B", kind: "participant", x: 120, y: 150,
        width: 80, height: 30, fill_opacity: 0.25, texts: []
      ),
    ]
    role_texts = [
      text_type.new(content: "warning", x: 10, y: 200, role: "warning"),
      text_type.new(content: "kind", x: 10, y: 220, role: "kind"),
    ]

    scene_type.new(
      width: 220, height: 240, banners: [], text_blocks: [
        scene_type::TextBlock.new(id: "roles", texts: role_texts),
      ], frames: [], fragments: [], notes: notes, dividers: dividers,
      bars: [], crosses: [], page_breaks: [], heads: heads, lifelines: [],
      arrows: [arrow]
    )
  end

  let(:document) do
    REXML::Document.new(described_class.new.render(scene).to_xml)
  end

  let(:matches) { ->(xpath) { REXML::XPath.match(document, xpath) } }

  def arrow_mark_attributes
    [
      matches.call("//g[@id='arrow-residual']/path/@stroke-dasharray")
        .map(&:value),
      matches.call("//g[@id='arrow-residual']/polygon/@fill").map(&:value),
      matches.call("//g[@id='arrow-residual']/circle").length,
      matches.call("//g[@id='arrow-residual']/line/@stroke-width").map(&:value),
    ]
  end

  def optional_opacities
    [
      matches.call("//g[starts-with(@id, 'note-')]/path/@fill-opacity")
        .map(&:value),
      matches.call("//g[@id='participant-A-150.0']/rect/@fill-opacity")
        .map(&:value),
      matches.call("//g[@id='participant-B-150.0']/rect/@fill-opacity")
        .map(&:value),
      matches.call("//g[starts-with(@id, 'note-')]/g[@transform]").length,
    ]
  end

  def role_typography
    %w[warning kind].map do |role|
      text = matches.call("//g[@id='roles']/text[.='#{role}']").first
      [text.attributes[role == "warning" ? "font-family" : "font-style"],
       text.attributes["font-size"]]
    end
  end

  it "draws every residual arrow mark and dashed shaft", :aggregate_failures do
    expect(arrow_mark_attributes)
      .to eq([["6,4"], ["#ffffff"], 1, %w[4.0 2.0]])
  end

  it "keeps optional note and head opacity absent or explicit",
     :aggregate_failures do
    expect(optional_opacities).to eq([["0.5"], [], ["0.25"], 0])
  end

  it "draws a divider label only when its text exists", :aggregate_failures do
    expect(matches.call("//g[@id='divider-100.0']/rect")).to be_empty
    expect(matches.call("//g[@id='divider-120.0']/rect").length).to eq(1)
  end

  it "uses warning and kind typography fallbacks", :aggregate_failures do
    expect(role_typography)
      .to eq([["monospace", "10"], ["italic", "11.9"]])
  end
end
