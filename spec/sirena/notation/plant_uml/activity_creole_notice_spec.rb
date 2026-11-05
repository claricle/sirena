# frozen_string_literal: true

require "spec_helper"
require_relative "activity/activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity do
  include ActivityHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def marks(scene, kind)
    scene.marks.select { |m| m.kind == kind }
  end

  def tspans(svg)
    REXML::XPath.match(REXML::Document.new(svg), "//tspan")
  end

  def decorated(svg, attribute)
    tspans(svg).select { |t| t.attributes[attribute] }.map(&:text)
  end

  describe "creole inside an action" do
    it "underlines `__x__` and keeps the plain words", :aggregate_failures do
      svg = render(":process only\n__sequence__ and __activity__ diagrams;")

      expect(decorated(svg, "text-decoration"))
        .to eq(%w[sequence activity])
      expect(svg_texts(svg)).to include("process only")
      expect(svg).not_to include("__")
    end

    it "bolds `**x**` inside a multi-line arrow label" do
      svg = render(":a;\n-> can\nbe **very** long;\n:b;")

      expect(decorated(svg, "font-weight")).to eq(["very"])
    end

    it "bolds an action's `<b>` tag" do
      expect(decorated(render(":a <b>bold</b> c;"), "font-weight"))
        .to eq(["bold"])
    end

    it "sizes the box by the text without its markers" do
      marked = layout(":**abc**;")
      plain = layout(":abc;")

      expect(marks(marked, :rect).first.attrs[:width])
        .to eq(marks(plain, :rect).first.attrs[:width])
    end

    it "leaves an unpaired marker literal" do
      expect(svg_texts(render(":a ** b;"))).to include("a ** b")
    end
  end

  describe "the old `#colour:` action syntax" do
    let(:svg) { render("start\n#pink:a;\n#lightgray:b;\nstop") }

    def notice(colour)
      "This syntax is deprecated, you must add <<##{colour}>> at the end " \
        "of the line, after the ';'"
    end

    it "prints one monospace notice per use, in order" do
      notes = REXML::XPath.match(REXML::Document.new(svg),
                                 "//text[@font-family='monospace']")

      expect(notes.map(&:text)).to eq(%w[pink lightgray].map { |c| notice(c) })
    end

    it "draws the notice in PlantUML's yellow box", :aggregate_failures do
      expect(svg).to include('fill="#FFFFCC"', 'stroke="#FFDD88"',
                             'stroke-width="3"')
    end

    it "does not paint the action", :aggregate_failures do
      expect(svg).not_to include('fill="pink"')
      expect(svg).not_to include('fill="lightgray"')
    end

    it "pushes the diagram below the notice" do
      with = marks(layout("#pink:a;"), :rect).last.attrs[:y]
      without = marks(layout(":a;"), :rect).last.attrs[:y]

      expect(with - without).to be_within(0.01).of(21.6406)
    end

    it "prints nothing for the current syntax" do
      expect(render(":a;")).not_to include("deprecated")
    end

    it "keeps the notice inside the canvas", :aggregate_failures do
      scene = layout("#pink:a;")
      box = marks(scene, :rect).find { |m| m.attrs[:role] == :warning }.attrs

      expect(box[:x] + box[:width]).to be <= scene.width
      expect(box[:y] + box[:height]).to be <= scene.height
    end
  end

  describe "a fork bar" do
    it "is a grey rounded slab", :aggregate_failures do
      svg = render("fork\n:a;\nfork again\n:b;\nend fork")

      expect(svg).to include('fill="#555555"', 'stroke="#555555"',
                             'rx="2.5"')
    end
  end
end
