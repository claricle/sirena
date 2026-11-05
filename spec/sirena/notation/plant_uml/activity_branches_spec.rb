# frozen_string_literal: true

require "spec_helper"
require_relative "activity/activity_helpers"

# Activity behaviour the parser, layout and render specs leave untouched:
# notes on the right, swimlane exits, bars, loops and the refusals of the
# legacy syntax.
RSpec.describe Sirena::Notation::PlantUML::Activity do
  include ActivityHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def refusal(body)
    parse(body)
  rescue Sirena::Notation::PlantUML::UnsupportedConstructError => e
    e
  end

  def top_of(scene, text)
    index = scene.marks.index do |m|
      m.kind == :text && m.attrs[:content] == text
    end
    scene.marks[0...index].reverse.find { |m| m.kind == :rect }.attrs[:y]
  end

  describe "arrows" do
    it "ignores a bare # as an arrow colour", :aggregate_failures do
      diagram = parse(":a;\n-[#]->\n:b;")

      expect(edge(diagram, "a", "b").colour).to be_nil
      expect(svg_texts(render(":a;\n-[#]->\n:b;"))).to include("a", "b")
    end

    it "draws no line for an arrow from an action to itself" do
      plain = render("(*) --> \"A\"")

      expect(render("(*) --> \"A\"\n\"A\" --> \"A\"").scan("<line").size)
        .to eq(plain.scan("<line").size)
    end
  end

  describe "notes" do
    it "draws a note on the right of an action", :aggregate_failures do
      svg = render(":a;\nnote right: beside")

      expect(svg_texts(svg)).to include("a", "beside")
    end

    it "draws a note on the left of an action" do
      expect(svg_texts(render(":a;\nnote left: before"))).to include("before")
    end
  end

  describe "swimlanes" do
    it "leaves a decision towards the lane on its left", :aggregate_failures do
      svg = render("|A|\nstart\n:x;\n|B|\nif (ok?) then (yes)\n|A|\n:y;\n" \
                   "else (no)\n|B|\n:z;\nendif\n|A|\nstop")

      expect(svg_texts(svg)).to include("A", "B", "ok?", "y", "z")
    end

    it "draws no band for a lane without nodes", :aggregate_failures do
      svg = render("|A|\n:x;\n|Empty|\n|B|\n:y;")

      expect(svg_texts(svg)).to include("A", "B")
      expect(svg_texts(svg)).not_to include("Empty")
    end
  end

  describe "legacy syntax" do
    it "stretches a bar over its neighbours and keeps a lone bar",
       :aggregate_failures do
      svg = render("(*) --> ===B1===\n===B1=== --> \"Left\"\n" \
                   "===B1=== --> \"Right\"\n\"Left\" --> ===B2===\n" \
                   "\"Right\" --> ===B2===\n===B2=== --> (*)\n" \
                   "===Alone=== --> ===Alone===")

      expect(svg_texts(svg)).to include("Left", "Right")
    end

    it "opens an if with no flow before it", :aggregate_failures do
      diagram = parse("(*) --> \"A\"\n\"A\" --> \"B\"\nif \"ok\" then\n" \
                      "--> \"C\"\nendif\n--> (*)")

      expect(kinds(diagram)).to include(:decision)
      expect(kinds(diagram)).not_to include(:merge)
    end

    it "opens an if as the first statement" do
      diagram = parse("if \"go\" then\n(*) --> \"X\"\nendif")

      expect(kinds(diagram)).to include(:decision)
    end

    it "refuses an arrow that has no source" do
      error = refusal("--> \"A\"\n(*) --> \"B\"")

      expect(error.message).to include("arrow without a source")
    end

    it "starts a flow at a bar" do
      diagram = parse("==Fork== --> \"A\"\n\"A\" --> (*)")

      expect(kinds(diagram)).to include(:bar)
    end
  end

  describe "loops" do
    it "ranks an exit whose paths rejoin below a loop", :aggregate_failures do
      scene = layout("(*) --> \"A\" as a\na --> \"B\" as b\nb --> a\n" \
                     "a --> \"X\" as x\nx --> \"Y\" as y\nx --> \"Z\" as z\n" \
                     "y --> \"W\" as w\nz --> w\nw --> (*)")

      expect(top_of(scene, "X")).to be > top_of(scene, "B")
      expect(top_of(scene, "W")).to be > top_of(scene, "Y")
    end
  end
end
