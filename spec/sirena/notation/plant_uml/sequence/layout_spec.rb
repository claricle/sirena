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

  describe "notes" do
    it "centres a note over one participant on its lifeline" do
      scene = scene_of("A -> B", "note over A: hi")
      head = top_heads(scene).first

      expect(scene.notes.first.path[/M (\S+)/, 1].to_f)
        .to be < head.x + (head.width / 2)
    end

    it "keeps a left note of the first participant inside the canvas" do
      scene = scene_of("A -> B", "note left of A: a long long long note")

      expect(scene.notes.first.path[/M (\S+)/, 1].to_f).to be >= 20.0
    end

    it "hangs a right note beside the rightmost end of its message" do
      scene = scene_of("B -> A", "note right: x")
      head = top_heads(scene).last

      expect(scene.notes.first.texts.first.x).to be > head.x + (head.width / 2)
    end

    it "gives a hnote no fold and a note one" do
      folds = %w[note hnote].map do |word|
        scene_of("A -> B", "#{word} over A: x").notes.first.fold_path
      end

      expect(folds.map(&:nil?)).to eq([false, true])
    end

    it "makes a two-line note taller than a one-line note" do
      heights = [%w[note over A: a], %w[note over A: a\\nb]].map do |words|
        scene_of("A -> B", words.join(" ")).height
      end

      expect(heights.last).to be > heights.first
    end
  end

  describe "blocks" do
    it "frames a block around the messages inside it" do
      scene = scene_of("A -> B", "alt ok", "B -> C", "end")

      expect(scene.fragments.size).to eq(1)
    end

    it "spans only the participants used inside the block" do
      scene = scene_of("A -> B", "B -> C", "alt ok", "B -> C", "end")
      first = top_heads(scene).first

      expect(scene.fragments.first.x).to be > first.x + first.width
    end

    it "draws one dashed line per else" do
      scene = scene_of("alt a", "A -> B", "else b", "B -> A", "end")

      expect(scene.fragments.first.separators.size).to eq(1)
    end

    it "keeps an inner block inside its outer block" do
      scene = scene_of("alt a", "loop b", "A -> B", "end", "end")
      inner, outer = scene.fragments

      expect(inner.x).to be > outer.x
    end

    it "lengthens the canvas for every block row" do
      plain = scene_of("A -> B").height
      framed = scene_of("alt a", "A -> B", "end").height

      expect(framed).to be > plain
    end
  end

  describe "dividers" do
    it "draws a divider across every lifeline" do
      divider = scene_of("A -> B", "== x ==").dividers.first
      xs = divider.lines.first.then { |line| [line.x1, line.x2] }

      expect(xs.last - xs.first).to be > 100
    end

    it "labels the divider" do
      divider = scene_of("A -> B", "== Phase ==").dividers.first

      expect(divider.texts.first.content).to eq("Phase")
    end
  end

  describe "activation bars" do
    it "spans from the activating arrow to the deactivating one" do
      bar = scene_of("A -> B ++", "B -> A --").bars.first

      expect(bar.height).to eq(40.0)
    end

    it "closes a bar still open at the end of the diagram" do
      expect(scene_of("A -> B", "activate B").bars.size).to eq(1)
    end

    it "shifts a nested bar right of the outer one" do
      scene = scene_of("A -> B ++", "A -> B ++", "B -> A --", "B -> A --")
      xs = scene.bars.map(&:x)

      expect(xs.uniq.size).to eq(2)
    end
  end
end
