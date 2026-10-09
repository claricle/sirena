# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

module PlantUmlSequenceSceneHelpers
  def scene_of(*lines)
    source = "@startuml\n#{lines.join("\n")}\n@enduml\n"
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    parsed.transform.new.call(parsed.diagram)
  end

  def top_heads(scene)
    scene.heads.first(scene.lifelines.size)
  end
end

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include PlantUmlSequenceSceneHelpers

  it "places a head at the top and at the foot of each lifeline" do
    expect(scene_of("A -> B").heads.size).to eq(4)
  end

  it "draws one lifeline per participant" do
    expect(scene_of("A -> B", "B -> C").lifelines.size).to eq(3)
  end

  it "orders heads left to right by first mention" do
    xs = top_heads(scene_of("A -> B", "B -> C")).map(&:x)

    expect(xs).to eq(xs.sort)
  end

  it "keeps neighbouring heads from overlapping" do
    a, b = top_heads(scene_of("A -> B"))

    expect(a.x + a.width).to be < b.x
  end

  it "widens the gap to fit a long label" do
    label = "x" * 80
    a, b = top_heads(scene_of("A -> B : #{label}"))

    expect(b.x - (a.x + a.width)).to be > 300
  end

  it "stacks messages in source order" do
    arrows = scene_of("A -> B", "B -> A").arrows
    ys = arrows.map { |arrow| arrow.path[/M \S+ (\S+)/, 1].to_f }

    expect(ys.last - ys.first).to eq(40.0)
  end

  it "points a reversed arrow at the participant on the left" do
    arrow = scene_of("A -> B", "B -> A").arrows.last
    tip = arrow.marker_points.split.first.split(",").first.to_f

    expect(tip).to be < arrow.path[/M (\S+)/, 1].to_f
  end

  it "fills the head of -> and leaves ->> open" do
    filled = scene_of("A -> B", "A ->> B").arrows.map(&:marker_filled)

    expect(filled).to eq([true, false])
  end

  it "makes room right of the last participant for a self message" do
    scene = scene_of("A -> A : long long long long long msg")

    expect(scene.width).to be > top_heads(scene).first.width + 150
  end

  it "frames a box and shifts the heads below its title" do
    scene = scene_of('box "G"', "participant A", "endbox")

    expect([scene.frames.size, scene.heads.first.y]).to eq([1, 46.0])
  end
end
