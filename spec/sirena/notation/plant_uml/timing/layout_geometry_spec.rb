# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# Lane heights and offsets measured on PlantUML 1.2026.6 (corpus 10-1-2).
RSpec.describe Sirena::Notation::PlantUML::Timing::Layout,
               :aggregate_failures do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.register(Sirena::Notation::PlantUML) unless
      Sirena::Notation.ids.include?(Sirena::Notation::PlantUML.id)
  end

  let(:all_lanes) do
    <<~PUML
      clock "C" as C with period 50
      binary "B" as B
      concise "N" as N
      robust "R" as R
      analog "A" as A
      @0
      N is a
      R is Idle
      A is 0
      @100
      B is high
      N is b
      R is Processing
      A is 3
      @300
      R is Waiting
      A is 1
    PUML
  end
  let(:doc) { render(all_lanes) }

  def render(body)
    REXML::Document.new(Sirena.render("@startuml\n#{body}\n@enduml",
                                      notation: :plantuml))
  end

  def numbers(doc, path, attribute)
    REXML::XPath.match(doc, path).map { |e| e.attributes[attribute].to_f }
  end

  # [x1, x2, y] of every horizontal rule.
  def rules(doc)
    REXML::XPath.match(doc, "//line")
      .select { |l| l.attributes["y1"] == l.attributes["y2"] }
      .map { |l| l.attributes.values_at(*%w[x1 x2 y1]).map { _1.value.to_f } }
  end

  # The y of each rule that runs the whole width from the left margin.
  def lane_tops(doc)
    full = rules(doc).select { |x1, *| x1.to_i == 20 }
    reach = full.map { |_, x2, _| x2 }.max
    full.select { |_, x2, _| x2 >= reach }.map(&:last).sort
  end

  def text(doc, content)
    REXML::XPath.match(doc, "//text").find { |t| t.text == content }
  end

  def robust(states)
    changes = states.each_with_index.map { |s, i| "@#{i * 100}\nR is #{s}" }
    render(%(robust "R" as R\n#{changes.join("\n")}))
  end

  it "starts the lanes 20 pixels from the top and the left" do
    expect(lane_tops(doc).first).to eq(20.0)
    expect(text(doc, "C").attributes["x"]).to eq("25.0")
  end

  it "gives each lane the height the JAR gives it" do
    gaps = lane_tops(doc).each_cons(2).map { |a, b| (b - a).round(2) }

    expect(gaps).to eq([47.49, 47.49, 56.49, 85.49])
  end

  it "ends the analog lane 117.49 below its top" do
    bottom = numbers(doc, "//line", "y1").max

    expect((bottom - lane_tops(doc).last).round(2)).to eq(117.49)
  end

  it "grows a robust lane by 20 pixels a state" do
    heights = %w[a a,b a,b,c].map do |names|
      doc = robust(names.split(","))
      (numbers(doc, "//line", "y1").max - lane_tops(doc).first).round(2)
    end

    expect(heights).to eq([45.49, 65.49, 85.49])
  end

  it "sits a digital signal 25.49 and 39.49 below the lane's top" do
    path = render("binary \"B\" as B\n@0\nB is low\n@100\nB is high")
    levels = REXML::XPath.first(path, "//path").attributes["d"]
      .scan(/[ML] [\d.]+ ([\d.]+)/).flatten.map { |y| (y.to_f - 20).round(2) }

    expect(levels.uniq).to contain_exactly(25.49, 39.49)
  end

  it "left-aligns robust state names at x=25" do
    expect(text(doc, "Processing").attributes["x"]).to eq("25.0")
    expect(text(doc, "Processing").attributes["text-anchor"]).to eq("start")
  end

  it "right-aligns the analog bounds against the plot" do
    expect(text(doc, "3.0").attributes["text-anchor"]).to eq("end")
  end

  it "cuts a concise lane's hexagon 12 in and opens its last end" do
    paths = render("concise \"N\" as N\n@0\nN is a\n@100\nN is b")
      .then { |d| REXML::XPath.match(d, "//path") }
      .map { |p| p.attributes["d"] }

    expect(paths.first).to match(/Z/i)
    expect(paths.last).not_to match(/Z/i)
  end

  it "names the analog bounds as PlantUML prints a number" do
    doc = render("analog \"A\" as A\n@0\nA is -5\n@100\nA is 10.25")

    expect(REXML::XPath.match(doc, "//text").map(&:text))
      .to include("-5.0", "10.25")
  end

  it "makes the canvas 20 pixels past the frame" do
    frame = numbers(doc, "//line", "x1").max

    expect(doc.root.attributes["width"].to_f).to be_within(1.5).of(frame + 21)
  end
end
