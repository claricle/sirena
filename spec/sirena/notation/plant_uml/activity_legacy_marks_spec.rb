# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require_relative "activity/activity_helpers"

# What the PlantUML JAR draws for the legacy `(*) -->` syntax and for
# swimlanes, which the model-level specs leave alone: one end node, a bare
# diamond with its condition beside it, a bar without its name, and bands
# filled the length of their lane.
RSpec.describe Sirena::Notation::PlantUML::Activity do
  include ActivityHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:legacy) do
    "(*) --> \"Init\"\nif \"Some Test\" then\n-->[true] \"Act\"\n" \
      "-right-> (*)\nelse\n->[false] \"Other\"\n-->[Ending] (*)\nendif\n"
  end

  def lane_names
    %w[One Two]
  end

  def diamond_left(svg)
    four = elements(svg, "polygon").find do |polygon|
      polygon.attributes["points"].split.length == 4
    end
    four.attributes["points"].split.map { |p| p.split(",").first.to_f }.min
  end

  def elements(svg, name)
    REXML::XPath.match(REXML::Document.new(svg).root,
                       "//*[local-name()='#{name}']")
  end

  describe "the legacy syntax" do
    it "ends every arrow to (*) at one node" do
      expect(parse(legacy).nodes.count { |n| n.kind == :stop }).to eq(1)
    end

    it "marks a decision and a bar as legacy" do
      diagram = parse("(*) --> ===B===\n===B=== --> \"X\"\nif \"c\" then\n" \
                      "--> \"Y\"\nendif")
      expect(diagram.nodes.select(&:legacy).map(&:kind))
        .to contain_exactly(:bar, :decision)
    end

    it "marks nothing in the new syntax as legacy" do
      expect(parse("start\nif (c) then (y)\n:a;\nendif\nstop").nodes
        .none?(&:legacy)).to be(true)
    end

    it "draws a four-point diamond, not a hexagon, for a condition" do
      points = elements(render(legacy), "polygon").map do |polygon|
        polygon.attributes["points"].split.length
      end
      expect(points.grep(4..)).to eq([4])
    end

    it "writes the condition outside the diamond, to its left",
       :aggregate_failures do
      svg = render(legacy)
      text = elements(svg, "text").find { |t| t.texts.join == "Some Test" }
      expect(text.attributes["text-anchor"]).to eq("end")
      expect(text.attributes["x"].to_f).to be < diamond_left(svg)
    end

    it "draws a grey bar and no name beside it", :aggregate_failures do
      svg = render("(*) --> ===B1===\n===B1=== --> \"X\"")
      expect(svg_texts(svg)).not_to include("B1")
      expect(svg).to include('fill="#555555"')
    end

    it "keeps a fork bar of the new syntax black" do
      svg = render("start\nfork\n:a;\nfork again\n:b;\nend fork\nstop")
      expect(svg).to include('fill="#000000"')
    end
  end

  describe "swimlane bands" do
    let(:svg) { render("|#pink|One|\nstart\n:a;\n|Two|\n:b;\nstop") }

    it "fills the whole lane with its colour" do
      expect(elements(svg, "rect").map { |r| r.attributes["fill"] })
        .to include("pink")
    end

    it "leaves an uncoloured lane unfilled" do
      expect(elements(svg, "rect").map { |r| r.attributes["fill"] })
        .to include("none")
    end

    it "draws no header box over the lane" do
      expect(elements(svg, "rect").map { |r| r.attributes["fill"] })
        .not_to include("#E2E2F0")
    end

    it "rules each side of a lane in black" do
      rules = elements(svg, "path").select do |p|
        p.attributes["stroke"] == "#000000"
      end
      expect(rules.length).to eq(4)
    end

    it "sets the lane name large when the band holds it" do
      sizes = elements(svg, "text").filter_map do |t|
        t.attributes["font-size"] if lane_names.include?(t.texts.join)
      end
      expect(sizes).to eq(%w[18 18])
    end

    it "keeps a name that is too wide for its band at the body size" do
      wide = "|#pink|An_exceedingly_long_swimlane_name|\nstart\n:a;\nstop"
      size = elements(render(wide), "text").find do |t|
        t.texts.join == "An_exceedingly_long_swimlane_name"
      end.attributes["font-size"]
      expect(size).to eq("12")
    end
  end
end
