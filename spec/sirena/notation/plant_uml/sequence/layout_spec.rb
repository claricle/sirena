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

  def teoz_scene(*lines)
    scene_of("!pragma teoz true", *lines)
  end

  def arrow_ys(scene)
    scene.arrows.map { |arrow| arrow.path[/M \S+ (\S+)/, 1].to_f }
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
    tip = arrow.marks.first.points.split.first.split(",").first.to_f

    expect(tip).to be < arrow.path[/M (\S+)/, 1].to_f
  end

  it "fills the head of -> and leaves ->> open" do
    arrows = scene_of("A -> B", "A ->> B").arrows
    filled = arrows.map { |arrow| arrow.marks.first.filled }

    expect(filled).to eq([true, false])
  end

  describe "arrow ends" do
    def marks_of(line)
      scene_of(line).arrows.first.marks
    end

    def numbers_of(line)
      scene_of(line).arrows.first.path.scan(/-?\d+\.?\d*/).map(&:to_f)
    end

    it "draws a cross as two heavy lines" do
      marks = marks_of("A ->x B")

      expect(marks.map { |m| [m.kind, m.heavy] }).to eq([["line", true]] * 2)
    end

    it "stops the shaft 11.5 inside a cross" do
      expect(numbers_of("A ->x B")[2]).to eq(numbers_of("A -> B")[2] - 11.5)
    end

    it "draws a ring before the head it belongs to" do
      expect(marks_of("A o-> B").map(&:kind)).to eq(%w[circle polygon])
    end

    it "starts the shaft 4 inside a ring with no head" do
      expect(numbers_of("A o-> B")[0]).to eq(numbers_of("A -> B")[0] + 4.0)
    end

    it "draws the half head of a backslash on the upper side only" do
      sides = marks_of("A -\\ B").first.points.split.map do |pair|
        pair.split(",").last.to_f
      end

      expect(sides.max).to eq(numbers_of("A -> B")[1])
    end

    it "loops a message written <- to its sender on the left" do
      numbers = numbers_of("A <- A : hi")

      expect(numbers[2]).to eq(numbers[0] - 36)
    end

    it "anchors the label of a left loop at its end" do
      arrow = scene_of("A <- A : hi").arrows.first

      expect(arrow.texts.first).to have_attributes(
        anchor: "end", x: numbers_of("A <- A : hi")[2] - 6,
      )
    end

    it "keeps a left loop of the first participant on the canvas" do
      expect(numbers_of("A <- A : hi").min).to be >= 0
    end
  end

  describe "messages with no participant at one end" do
    let(:long) { "x" * 80 }

    def ends_of(scene)
      scene.arrows.map do |arrow|
        arrow.path.scan(/-?\d+\.?\d*/).map(&:to_f).values_at(0, 2)
      end
    end

    def first_run(line)
      ends_of(scene_of(line)).first
    end

    def lifeline(scene, index)
      scene.lifelines[index].x1
    end

    it "starts a [-> message at the left edge of the canvas" do
      expect(first_run("[-> A : hi").first).to eq(0.0)
    end

    it "pushes the heads right to fit the label of a [-> message" do
      near = top_heads(scene_of("[-> A : hi")).first.x
      far = top_heads(scene_of("[-> A : #{long}")).first.x

      expect(far).to be > near + 300
    end

    it "pushes the heads right when the target is not the first" do
      scene = scene_of("participant A", "participant B",
                       "[-> B : #{long}")

      expect(lifeline(scene, 1)).to be > 400
    end

    it "ends a ->] message right of the last head and inside the canvas" do
      scene = scene_of("participant A", "participant B", "A ->] : hi")
      stop = ends_of(scene).first.last
      last = top_heads(scene).last

      expect([stop > last.x + last.width, stop < scene.width])
        .to eq([true, true])
    end

    it "ends every ->] message at the same place" do
      scene = scene_of("participant A", "participant B",
                       "A ->] : hi", "B ->] : there")

      expect(ends_of(scene).map(&:last).uniq.size).to eq(1)
    end

    it "carries a long ->] label past the last head" do
      scene = scene_of("A ->] : #{long}")

      expect(ends_of(scene).first.last).to be > 400
    end

    it "keeps the end of a long ->] label on the canvas" do
      scene = scene_of("A ->] : #{long}")

      expect(scene.width).to be > ends_of(scene).first.last
    end

    it "pulls the end of a ->o] message 8 inside the edge" do
      plain = first_run("A ->] : hi").last
      ring = scene_of("A ->o] : hi").arrows.first.marks.find do |mark|
        mark.kind == "circle"
      end

      expect(ring.cx).to eq(plain - 8.0)
    end

    it "pulls the start of a [o-> message 8 inside the edge" do
      ring = scene_of("[o-> A : hi").arrows.first.marks.first

      expect(ring.cx).to eq(8.0)
    end

    it "runs a ->? message a label and 24 beyond its sender" do
      scene = scene_of("A ->? : hi", "A ->? : a longer label")
      short, long = ends_of(scene).map { |numbers| numbers.last - numbers[0] }

      expect([short > 24, long > short]).to eq([true, true])
    end

    it "runs a ?-> message back from its receiver" do
      start, stop = first_run("?->A : hi")

      expect(stop - start).to be > 24
    end

    it "keeps a ?-> message of the first head on the canvas" do
      expect(first_run("?->A : #{long}").min).to be >= 0
    end
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

    it "fills a bar with the colour it was opened with" do
      bar = scene_of("A -> B ++ #red", "B -> A --").bars.first

      expect(bar.fill).to eq("red")
    end

    it "shifts a nested bar right of the outer one" do
      scene = scene_of("A -> B ++", "A -> B ++", "B -> A --", "B -> A --")
      xs = scene.bars.map(&:x)

      expect(xs.uniq.size).to eq(2)
    end
  end

  describe "destroy" do
    let(:cross) { scene_of("A -> B !!").crosses }

    it "draws two strokes crossing on the lifeline of the receiver" do
      lifeline_x = scene_of("A -> B !!").lifelines.last.x1

      middles = cross.map { |line| (line.x1 + line.x2) / 2 }

      expect(middles).to all(eq(lifeline_x))
    end

    it "draws two strokes whose ends are opposite corners" do
      expect(cross.map { |line| line.y1 < line.y2 }.sort_by(&:to_s))
        .to eq([false, true])
    end

    it "draws no stroke without destroy" do
      expect(scene_of("A -> B").crosses).to be_empty
    end

    it "sits level with the arrow it follows" do
      scene = scene_of("A -> B", "destroy B")
      arrow_y = scene.arrows.first.path[/L [\d.]+ ([\d.]+)/, 1].to_f

      expect(scene.crosses.map { |line| (line.y1 + line.y2) / 2 })
        .to all(eq(arrow_y))
    end
  end

  describe "parallel rows" do
    it "draws a message on the row of the one before it" do
      scene = teoz_scene("A -> B", "& C -> D")

      expect(arrow_ys(scene).uniq.size).to eq(1)
    end

    it "continues below the row after a chain of parallel messages" do
      parallel = teoz_scene("A -> B", "& C -> D", "A -> B")
      single = teoz_scene("A -> B", "A -> B")

      expect(arrow_ys(parallel).last).to eq(arrow_ys(single).last)
    end

    it "continues below a taller parallel item" do
      scene = teoz_scene("A -> B", "& C -> C", "A -> B")

      expect(arrow_ys(scene).last - arrow_ys(scene).first).to eq(60.0)
    end

    it "continues below a taller message before a shorter parallel one" do
      scene = teoz_scene("A -> A", "& B -> C", "A -> B")

      expect(arrow_ys(scene).last - arrow_ys(scene).first).to eq(60.0)
    end

    it "puts a note beside the note before it at the same height" do
      scene = teoz_scene("A -> B", "note over A: a", "& note over B: b")
      tops = scene.notes.map { |note| note.texts.first.y }

      expect(tops.uniq.size).to eq(1)
    end

    it "opens a block level with the message before it" do
      scene = teoz_scene("A -> B", "& opt", "C -> D", "end")

      expect(scene.fragments.first.y).to eq(arrow_ys(scene).first)
    end

    it "draws a message beside a block that has just closed" do
      scene = teoz_scene("opt", "A -> B", "end", "& C -> C")

      expect(scene.arrows.last.path[/M \S+ (\S+)/, 1].to_f)
        .to eq(scene.fragments.first.y)
    end

    it "continues below a taller message beside a short block" do
      scene = teoz_scene("A -> A", "& opt", "end", "B -> C")

      expect(arrow_ys(scene).last - arrow_ys(scene).first).to eq(60.0)
    end
  end

  describe "hide footbox" do
    let(:shown) { scene_of("A -> B") }
    let(:hidden) { scene_of("hide footbox", "A -> B") }

    it "draws the heads at the top only" do
      expect(hidden.heads.map(&:y).uniq).to eq([shown.heads.first.y])
    end

    it "shortens the canvas by the height of a head" do
      expect(shown.height - hidden.height).to eq(shown.heads.first.height)
    end

    it "ends the lifelines where they ended" do
      expect(hidden.lifelines.map(&:y2)).to eq(shown.lifelines.map(&:y2))
    end
  end

  describe "participant heads" do
    it "makes every head at least the requested minimum plus 14 wide" do
      heads = top_heads(scene_of("skinparam MinClassWidth 100", "A -> B"))

      expect(heads.map(&:width)).to all(be >= 114.0)
    end

    it "keeps the default width when nothing is requested" do
      expect(top_heads(scene_of("A -> B")).map(&:width)).to all(be < 114.0)
    end

    it "writes the stereotype above the label" do
      head = top_heads(scene_of("participant C <<st>>", "C -> D")).first

      expect(head.texts.map(&:content)).to eq(["«st»", "C"])
    end

    it "makes the heads taller for a stereotype" do
      head = top_heads(scene_of("participant C <<st>>", "C -> D")).first

      expect(head.height).to eq(56.0)
    end
  end
end
