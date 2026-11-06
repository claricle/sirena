# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Radii, strokes, heights and arrowhead shapes are the PlantUML JAR 1.2026.6's
# own, from its SVG for each construct. Text is measured with Sirena's DejaVu
# Sans advances, not the JAR's face, so every x coordinate and width is
# Sirena's DejaVu-derived geometry and sits a few pixels from the JAR's.
RSpec.describe Sirena::Notation::PlantUML::Ebnf::Blocks do
  include_context "with an isolated notation registry"

  def render(rule)
    Sirena::Engine.new.render("@startebnf\n#{rule}\n@endebnf\n",
                              notation: :plantuml)
  end

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def advance(text)
    Sirena::TextMeasurement.measure_in(:dejavu, text, font_size: 14)[:width]
  end

  def paths(rule)
    render(rule).scan(/<path[^>]*>/).map do |tag|
      tag[/ d="([^"]*)"/, 1].gsub(/-?\d+\.\d+/) { |n| n.to_f.round(2).to_s }
    end
  end

  def tags(rule, name)
    render(rule).scan(/<#{name}\b[^>]*>/)
  end

  def attribute(tag, name)
    tag[/ #{name}="([^"]*)"/, 1]
  end

  def size(rule)
    svg = render(rule)
    [svg[/ width="([\d.]+)"/, 1], svg[/ height="([\d.]+)"/, 1]].map(&:to_f)
  end

  def points(rule)
    tags(rule, "polygon").map do |tag|
      attribute(tag, "points").scan(/-?[\d.]+/).map { |n| n.to_f.round(2) }
    end
  end

  def rects(rule)
    tags(rule, "rect").map do |tag|
      attributes = %w[x y width height]
      attributes.map { |name| attribute(tag, name).to_f.round(2) }
    end
  end

  def rounded(path)
    path.gsub(/-?\d+\.\d+/) { |n| n.to_f.round(3).to_s }
  end

  def stroke_widths(svg, tag)
    svg.scan(/<#{tag}[^>]*stroke-width="([^"]*)"/).flatten.uniq
  end

  def numbers(commands)
    commands.flat_map { |command| command.drop(1) }
  end

  describe Sirena::Notation::PlantUML::Ebnf::Blocks::Curves do
    it "bends a branch off the rail as the JAR's choice does" do
      commands = described_class.drop(40, 49.7324, 86.2207, 12.0)
      expect(commands[1]).to eq([:bezier, 49.0, 49.7324, 52.0, 52.7324, 52.0,
                                 61.7324])
    end

    it "bends back onto a branch's rail as the JAR's choice does" do
      commands = described_class.drop(40, 49.7324, 86.2207, 12.0)
      expect(commands[3]).to eq(
        [:bezier, 52.0, 83.2207, 55.0, 86.2207, 64.0, 86.2207],
      )
    end

    it "runs straight between the two bends of a choice" do
      expect(described_class.drop(40, 49.7324, 86.2207, 12.0)[2])
        .to eq([:line, 52.0, 74.2207])
    end

    it "bends in an S for a bypass, as the JAR's optional does" do
      commands = described_class.drop(40, 46.4883, 69.7324, 12.0, smooth: true)
      expect(numbers(commands.drop(1)).map { |n| n.round(4) }).to eq(
        [49.0, 46.4883, 52.0, 49.1104, 52.0, 58.1104,
         52.0, 67.1104, 55.0, 69.7324, 64.0, 69.7324],
      )
    end

    it "mirrors on the right edge" do
      commands = described_class.drop(100, 46.0, 86.0, -12.0)
      expect(commands[1]).to eq([:bezier, 91.0, 46.0, 88.0, 49.0, 88.0, 58.0])
    end
  end

  describe "the rails of a rule" do
    it "turns a choice in cubic curves, not quadratic ones" do
      expect(paths('r = "a" | "b" | "c";').first).to eq(
        "M 40.0 49.73 C 49.0 49.73 52.0 52.73 52.0 61.73 " \
        "L 52.0 74.22 C 52.0 83.22 55.0 86.22 64.0 86.22",
      )
    end

    it "turns an optional's bypass in one S" do
      expect(paths('r = [ "a" ];').first).to eq(
        "M 40.0 46.49 C 49.0 46.49 52.0 49.11 52.0 58.11 " \
        "C 52.0 67.11 55.0 69.73 64.0 69.73",
      )
    end

    it "draws a loop with the item on the lower rail and the line above" do
      width = (advance("a") + 10).round(2)
      expect(rects('r = { "a" };')).to eq([[79.0, 68.49, width, 26.49]])
    end

    it "rounds the loop-back line at the JAR's loop radius of 8" do
      expect(paths('r = { "a" };')).to include(
        "M 72.0 73.73 C 72.0 79.73 74.0 81.73 80.0 81.73",
        "M 72.0 73.73 L 72.0 69.49 C 72.0 63.49 74.0 61.49 80.0 61.49",
      )
    end

    it "loops back over the item of a one-or-more" do
      expect(tags('r = { "a" }-;', "line").map { |t| attribute(t, "y1") })
        .to include("41.488299999999995")
    end

    it "points the bypass arrowhead forward and the loop-back one back" do
      expect(points('r = { "a" };').first(2)).to eq(
        [[76.63, 43.49, 82.63, 46.49, 76.63, 49.49],
         [88.15, 58.49, 82.15, 61.49, 88.15, 64.49]],
      )
    end

    it "closes a rule with an arrowhead on its end rail" do
      expect(points('r = "a", "b", c;')).to eq(
        [[146.16, 46.73, 152.16, 49.73, 146.16, 52.73]],
      )
    end

    it "draws rails at 1.5" do
      expect(render('r = "a", "b";').scan(/<line[^>]*stroke-width="([^"]*)"/)
        .flatten.uniq).to eq(["1.5"])
    end

    it "draws the start dot at 2" do
      expect(render('r = "a", "b";')).to match(/<circle[^>]*stroke-width="2"/)
    end
  end

  describe "the size of a diagram" do
    {
      'r = "a", "b", c;' => [176, 88],
      'r = "a" | "b" | "c" | "d";' => [147, 198],
      'r = [ "a" ];' => [147, 108],
      'r = { "a" };' => [177, 120],
      'r = { "a" }-;' => [129, 100],
      'r = "x", { "a" | [ b ] }, ( "c" | "d" ), "e";' => [437, 180],
      %(r = "a";\ns = b, "c";) => [137, 156],
    }.each do |rule, expected|
      it "is #{expected.join('x')} for #{rule.inspect}" do
        expect(size(rule)).to eq(expected.map(&:to_f))
      end
    end
  end

  describe "the boxes" do
    it "leaves a terminal bare at half a pixel" do
      expect(tags('r = "a";', "rect").first)
        .to include('fill="none"', 'stroke-width="0.5"')
    end

    it "fills a reference and rounds it at 5" do
      expect(tags("r = a;", "rect").first)
        .to include('fill="#F1F1F1"', 'rx="5.0"', 'stroke-width="1.5"')
    end

    it "dashes a special sequence 5 on 5 off" do
      expect(tags("r = ? special seq ?;", "rect").first)
        .to include('stroke-dasharray="5,5"')
    end

    it "pads a special sequence's text by 18.8594" do
      width = attribute(tags("r = ? special seq ?;", "rect").first, "width")
      expect(width.to_f)
        .to be_within(0.001).of(advance("special seq") + 18.8594)
    end

    it "sets words at 14" do
      expect(tags('r = "a";', "text")).to all(include('font-size="14"'))
    end
  end

  describe "a choice of four" do
    it "stacks the branches 36.4883 apart, left aligned" do
      expect(rects('r = "a" | "b" | "c" | "d";').map { |box| box.first(2) })
        .to eq([[64.0, 36.49], [64.0, 72.98], [64.0, 109.46],
                [64.0, 145.95]])
    end
  end

  describe "nested constructs" do
    it "puts a choice with an optional in a loop as the JAR does" do
      expect(rects('r = "x", { "a" | [ b ] }, ( "c" | "d" ), "e";')
        .map { |box| box.first(2) }).to include([141.29, 71.73],
                                                [165.29, 128.22],
                                                [315.17, 72.98])
    end
  end
end
