# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# The numbers in the examples are the PlantUML JAR 1.2026.6's own: its SVG
# for `r = a | b | c;`, `r = [ a ];` and `r = { a };`.
RSpec.describe Sirena::Notation::PlantUML::Ebnf::Blocks do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def render(rule)
    Sirena::Engine.new.render("@startebnf\n#{rule}\n@endebnf\n",
                              notation: :plantuml)
  end

  def paths(rule)
    render(rule).scan(/<path[^>]*>/).map { |tag| tag[/ d="([^"]*)"/, 1] }
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
      expect(rounded(paths("r = a | b | c;").first)).to eq(
        "M 45.0 50.244 C 54.0 50.244 57.0 53.244 57.0 62.244 L 57.0 74.732 " \
        "C 57.0 83.732 60.0 86.732 69.0 86.732",
      )
    end

    it "turns an optional's bypass in one S" do
      expect(rounded(paths("r = [ a ];").first)).to eq(
        "M 45.0 37.0 C 54.0 37.0 57.0 39.622 57.0 48.622 " \
        "C 57.0 57.622 60.0 60.244 69.0 60.244",
      )
    end

    it "rounds the loop-back line above the item at the loop radius of 8" do
      expect(rounded(paths("r = { a };").first)).to eq(
        "M 118.784 74.244 L 118.784 62.0 C 118.784 56.0 116.784 54.0 " \
        "110.784 54.0 L 85.0 54.0 C 79.0 54.0 77.0 56.0 77.0 62.0 " \
        "L 77.0 74.244",
      )
    end

    it "draws rails at 1.5 and boxes at 0.5" do
      svg = render("r = a, b;")
      expect([stroke_widths(svg, "line"), stroke_widths(svg, "rect")])
        .to eq([["1.5"], ["0.5"]])
    end

    it "draws the start dot at 2" do
      expect(render("r = a, b;")).to match(/<circle[^>]*stroke-width="2"/)
    end
  end
end
