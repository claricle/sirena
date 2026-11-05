# frozen_string_literal: true

require "rexml/document"
require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  let(:boxed) do
    <<~PLANTUML
      @startuml
      box "Internal"
      participant Alice
      participant Bob
      end box
      participant C
      Alice -> Bob: hello there
      Bob -> C: 2
      @enduml
    PLANTUML
  end
  let(:fragmented) do
    <<~PLANTUML
      @startuml
      A -> B: go
      alt ok
      B --> A: yes
      end
      @enduml
    PLANTUML
  end

  def scene_of(source)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    parsed.transform.new.call(parsed.diagram)
  end

  def svg_of(source, theme: nil)
    svg = Sirena.render(source, notation: :plantuml, theme: theme)
    REXML::Document.new(svg)
  end

  def attribute_of(document, xpath, name)
    REXML::XPath.first(document, xpath).attributes[name]
  end

  def frame_stroke(document)
    attribute_of(document, "//*[starts-with(@id,'fragment-')]/rect", "stroke")
  end

  # JAR 1.2026.6 measures the heads at x=5, 100.29, 149.75 and the box at
  # x=1, width 142.75; sirena draws the same picture 15 points further right.
  it "spaces boxed heads as the JAR does" do
    heads = scene_of(boxed).heads.first(3).map(&:x)

    expect(heads.map { |x| (x - heads.first + 5).round(2) })
      .to eq([5.0, 100.29, 149.75])
  end

  it "pads a box by 4 and widens it for its bold-13 title overhang" do
    scene = scene_of(boxed)
    frame = scene.frames.first

    expect([frame.x, frame.width.round(2)])
      .to eq([scene.heads.first.x - 4, 142.75])
  end

  it "keeps a self-message minimum of 50 between neighbouring lifelines" do
    scene = scene_of("@startuml\nx -> x: start\nd -> d: next\n@enduml\n")
    centres = scene.heads.first(2).map { |h| h.x + (h.width / 2) }

    expect(centres.last - centres.first).to eq(50.0)
  end

  it "paints an unthemed fragment frame with the PlantUML skin" do
    expect(frame_stroke(svg_of(fragmented))).to eq("#000000")
  end

  it "draws an unthemed arrow one point wide" do
    document = svg_of(fragmented)

    expect(attribute_of(document, "//*[@id='message-1']/path", "stroke-width"))
      .to eq("1")
  end

  it "leaves a non-default theme unskinned" do
    document = svg_of(fragmented, theme: Sirena::Theme::Registry.get(:dark))

    expect(frame_stroke(document)).not_to eq("#000000")
  end
end
