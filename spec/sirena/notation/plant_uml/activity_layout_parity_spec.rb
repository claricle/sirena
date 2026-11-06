# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# Every number is read off the PlantUML JAR 1.2026.6 drawing the same
# unstyled source; the comment on each example names it.
RSpec.describe Sirena::Notation::PlantUML::Activity do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  def root_for(*lines)
    xml = Sirena::Engine.new.render("@startuml\n#{lines.join("\n")}\n@enduml\n")
    REXML::Document.new(xml).root
  end

  def match(root, name)
    REXML::XPath.match(root, "//*[local-name()='#{name}']")
  end

  def points(polygon)
    polygon.attributes["points"].split.map { |p| p.split(",").map(&:to_f) }
  end

  def hexagon(root)
    match(root, "polygon").map { |g| points(g) }.find { |p| p.size == 6 }
  end

  def diamonds(root)
    match(root, "polygon").map { |g| points(g) }.select do |pts|
      pts.size == 4 && pts.map(&:first).uniq.size == 3
    end
  end

  def boxes(root)
    match(root, "rect").reject { |r| r.attributes["fill"] == "none" }
      .sort_by { |r| [r.attributes["y"].to_f, r.attributes["x"].to_f] }
  end

  def num(element, name)
    element.attributes[name].to_f
  end

  def top(box) = num(box, "y")
  def bottom(box) = num(box, "y") + num(box, "height")
  def centre(box) = num(box, "x") + (num(box, "width") / 2)
  def span(pts, axis) = pts.map { |pt| pt[axis] }.minmax

  def routes(root)
    match(root, "path").map do |path|
      path.attributes["d"].scan(/(-?[\d.]+),(-?[\d.]+)/)
        .map { |pt| pt.map(&:to_f) }
    end
  end

  def texts(root)
    match(root, "text").to_h { |t| [t.text.to_s, t] }
  end

  # The bar, the two steps it joins and the lone step beside them.
  def fork_parts(root)
    bars, steps = boxes(root).partition { |b| num(b, "height") < 7 }
    steps = steps.sort_by { |b| num(b, "x") }
    [bars.first, steps.first(2), steps.last]
  end

  # Where the arrow into the bar and the arrow to the lone step land.
  def heads(fork, other)
    [(centre(fork.first) + centre(fork.last)) / 2, centre(other)]
  end

  def split(root)
    rows = boxes(root)
    [rows, hexagon(root), diamonds(root)]
  end

  let(:two_way) do
    root_for("start", ":a;", "if (wide decision text here?) then (yes)", ":x;",
             "else (no)", ":y;", "endif", ":b;")
  end

  describe "the column a decision hangs from" do
    # JAR: heads at the hexagon's tips -10 and +10, trunk midway
    it "keeps the trunk midway between the two branches" do
      rows, hex, = split(two_way)
      trunk = span(hex, 0).sum / 2

      expect(trunk)
        .to be_within(0.01).of((centre(rows[1]) + centre(rows[2])) / 2)
    end

    it "lines the next step up on the same trunk" do
      rows, hex, = split(two_way)

      expect(centre(rows.last)).to be_within(0.01).of(span(hex, 0).sum / 2)
    end

    # JAR: branches 172.7 apart for a 152.7 wide hexagon
    it "stands the branches a hexagon's width plus 20 apart at least" do
      rows, hex, = split(two_way)
      width = span(hex, 0).then { |lo, hi| hi - lo }

      expect(centre(rows[2]) - centre(rows[1])).to be >= width + 20 - 0.01
    end

    # JAR: two long branches stand 20 apart edge to edge
    it "packs wide branches 20 apart" do
      root = root_for("if (c?) then (y)", ":one;", ":two;", "else (n)",
                      ":a very long action label here;", "endif")
      left, right = boxes(root).sort_by { |r| num(r, "x") }.values_at(0, -1)

      expect(num(right, "x") - (num(left, "x") + num(left, "width")))
        .to be_within(0.01).of(20.0)
    end
  end

  describe "the gap between rows" do
    let(:rows) { boxes(two_way) }
    let(:hex) { hexagon(two_way) }

    # JAR: a 89.13 -> decision 109.13, 20
    it "leaves 20 from a step to a decision" do
      expect(span(hex, 1).first - bottom(rows.first)).to be_within(0.01).of(20)
    end

    # JAR: decision bottom 133.13 -> branch top 143.13, 10
    it "leaves 10 from a decision to its branches" do
      expect(top(rows[1]) - span(hex, 1).last).to be_within(0.01).of(10)
    end

    # JAR: branch bottom 177.27 -> merge top 183.27, 6
    it "leaves 6 from a branch to the diamond that closes it" do
      merge = diamonds(two_way).first

      expect(span(merge, 1).first - bottom(rows[1])).to be_within(0.01).of(6)
    end

    # JAR: merge bottom 207.27 -> next step 227.27, 20
    it "leaves 20 from the closing diamond to the next step" do
      merge = diamonds(two_way).first

      expect(top(rows.last) - span(merge, 1).last).to be_within(0.01).of(20)
    end

    # JAR: "yes" on a straight exit asks 24.4; unlabelled asks 20
    it "leaves room for a label on the exit that drops straight" do
      [["if (r?) then (yes)", 24.37], ["if (r?) then", 20.0]].each do |h, want|
        root = root_for("start", h, ":only;", "endif")
        expect(top(boxes(root).first) - span(hexagon(root), 1).last)
          .to be_within(0.05).of(want)
      end
    end

    # JAR 6-15: a three line label between two steps, 67.2
    it "adds a label's height and 28.33 between two steps" do
      root = root_for(":foo1;", "-> one", "two", "three;", ":foo2;")
      first, second = boxes(root)

      expect(top(second) - bottom(first)).to be_within(0.1).of(67.2)
    end
  end

  describe "the width of an arrow's label" do
    let(:root) do
      root_for(":foo1;", "if (test) then", ":foo2;",
               "-> a long label on the arrow;", ":foo3;", "else", ":foo4;",
               "endif")
    end

    # JAR 6-15: the label ends 20 before the next column's box
    it "keeps the next column 20 clear of the label" do
      text = "a long label on the arrow"
      width = Sirena::TextMeasurement.measure(text, font_size: 11)[:width]
      right = num(texts(root)[text], "x") + width

      expect(num(boxes(root).max_by { |b| num(b, "x") }, "x") - right)
        .to be >= 19.9
    end
  end

  describe "a fork on a branch" do
    let(:root) do
      root_for("start", "if (multiprocessor?) then (yes)", "fork",
               ":Treatment 1;", "fork again", ":Treatment 2;", "end fork",
               "else (monoproc)", ":Treatment 1;", ":Treatment 2;", "endif")
    end

    # JAR 6-10-4: the bar runs 12 left and 14 right of its two steps
    it "reaches 13 past the steps it joins" do
      bar, fork, = fork_parts(root)
      edges = [num(fork.first, "x") - num(bar, "x"),
               num(bar, "x") + num(bar, "width") -
                 (num(fork.last, "x") + num(fork.last, "width"))]

      expect(edges).to all(be_within(1.01).of(13.0))
    end

    # JAR 6-10-4: the next branch stands 20 clear of the bar
    it "stands the next branch 20 clear of the bar" do
      bar, _, other = fork_parts(root)
      expect(num(other, "x") - (num(bar, "x") + num(bar, "width")))
        .to be_within(0.01).of(20.0)
    end

    # JAR 6-10-4: the arrow down to the bar lands midway between its steps
    it "lands the arrow into the bar midway between its steps" do
      bar, fork, other = fork_parts(root)
      entry = routes(root).find do |pts|
        pts.size == 3 && (pts.last.last - top(bar)).abs < 0.01
      end

      expect(entry.last.first).to be_within(0.01).of(heads(fork, other).first)
    end

    # JAR 6-10-4: the decision hangs midway between the two heads
    it "hangs the decision midway between the two heads" do
      _, fork, other = fork_parts(root)

      expect(span(hexagon(root), 0).sum / 2)
        .to be_within(0.01).of(heads(fork, other).sum / 2)
    end
  end

  describe "a decision with three or more branches" do
    let(:root) do
      root_for("start", "switch (test?)", "case ( condition A )", ":T1;",
               "case ( condition B )", ":T2;", "case ( condition C )",
               ":T3;", "endswitch", "stop")
    end
    let(:steps) { boxes(root).sort_by { |b| num(b, "x") }.first(3) }

    # JAR 6-4: the decision stands 19 right of the middle of the outer
    # steps, a label's width counted
    it "hangs the decision off the middle of the block it spans" do
      label = Sirena::TextMeasurement.measure("condition C", font_size: 11)
      right = centre(steps.last) + 5 + label[:width] + 3.5
      left = centre(steps.first) - (num(steps.first, "width") / 2)

      expect(span(hexagon(root), 0).sum / 2)
        .to be_within(0.01).of((left + right) / 2)
    end

    # JAR 6-4: the branch under the decision jogs sideways 12 below it
    it "jogs the branch under the decision into its step" do
      hex = hexagon(root)
      jog = routes(root).find do |pts|
        pts.size == 4 && (pts.first.last - span(hex, 1).last).abs < 0.01
      end

      expect(jog[1].last - span(hex, 1).last).to be_within(0.01).of(11.97)
    end

    # JAR 6-4: 36 from the decision to the steps when a branch jogs
    it "leaves 36 from the decision to its steps" do
      expect(top(steps.first) - span(hexagon(root), 1).last)
        .to be_within(0.5).of(35.9)
    end
  end

  describe "the label on a decision's side exit" do
    let(:root) do
      root_for("if (c?) then (left)", ":a;", "else (right)", ":b;", "endif")
    end
    let(:hex) { hexagon(root) }

    # JAR 6-10-4, 6-25-2: the label stands above the run, ending at the tip
    it "ends at the left tip, above the run", :aggregate_failures do
      label = texts(root)["left"]

      expect(label.attributes["text-anchor"]).to eq("end")
      expect(num(label, "x")).to be_within(0.01).of(span(hex, 0).first)
      expect(num(label, "y"))
        .to be_within(0.01).of((span(hex, 1).sum / 2) - 2.32)
    end

    it "starts at the right tip", :aggregate_failures do
      label = texts(root)["right"]

      expect(label.attributes["text-anchor"]).to eq("start")
      expect(num(label, "x")).to be_within(0.01).of(span(hex, 0).last)
    end
  end

  describe "the legacy if" do
    let(:root) do
      Sirena::Engine.new.render(
        "@startuml\n(*) --> \"Init\"\nif \"Some Test\" then\n" \
        "-->[true] \"Yes\"\nelse\n-->[false] \"No\"\nendif\n@enduml\n",
      ).then { |xml| REXML::Document.new(xml).root }
    end

    # JAR 5-4: a bare 24 by 24 diamond, "Some Test" left of the arrow in
    it "draws no hexagon" do
      expect(hexagon(root)).to be_nil
    end

    it "draws the diamond 24 by 24" do
      sizes = [0, 1].map { |axis| span(diamonds(root).first, axis).reduce(:-) }

      expect(sizes).to all(be_within(1e-6).of(-24.0))
    end

    it "writes the question outside the diamond, to its left" do
      question = texts(root)["Some Test"]
      diamond = diamonds(root).first

      expect(num(question, "x")).to be < span(diamond, 0).first
    end
  end

  # JAR: the title of a partition is plain at 14
  it "draws a partition's title plain" do
    title = texts(root_for(":a;", "partition Part {", ":c;", "}"))["Part"]

    expect([title.attributes["font-weight"], num(title, "font-size")])
      .to eq([nil, 14.0])
  end

  # JAR: a note stands 20 from its step
  it "puts a note 20 from its step" do
    root = root_for(":a;", "note right: a note")
    step = boxes(root).first
    note = match(root, "polygon").map { |g| points(g) }.find { |p| p.size == 5 }

    expect(span(note, 0).first - (num(step, "x") + num(step, "width")))
      .to be_within(0.01).of(20.0)
  end
end
