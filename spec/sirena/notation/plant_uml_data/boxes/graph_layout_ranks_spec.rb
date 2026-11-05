# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUMLData::Boxes::GraphLayout do
  include_context "with an isolated notation registry"

  before do
    unless Sirena::Notation.ids.include?(Sirena::Notation::PlantUML.id)
      Sirena::Notation.register(Sirena::Notation::PlantUML)
    end
  end

  def render(body)
    Sirena.render("@startuml\n#{body}\n@enduml\n", notation: :plantuml)
  end

  def elements(svg, name)
    REXML::XPath.match(REXML::Document.new(svg), "//#{name}")
  end

  # The [x, y] of the box titled `name`: the rect whose top edge holds it.
  def corner(svg, name)
    text = elements(svg, "text").find { |t| t.text == name }
    rect = elements(svg, "rect").find { |r| holds?(r, text) }
    %w[x y].map { |axis| rect.attributes[axis].to_f }
  end

  def holds?(rect, text)
    rise = text.attributes["y"].to_f - rect.attributes["y"].to_f
    left = rect.attributes["x"].to_f
    rise.between?(0, 20) && left <= text.attributes["x"].to_f
  end

  def corners(svg, *names)
    names.map { |name| corner(svg, name) }
  end

  let(:capitals) do
    File.read(File.expand_path(
                "../../../../fixtures/plantuml_boxes/lrg-4-6-5.puml", __dir__
              ))
  end

  describe "ranks" do
    it "puts the end of a one-dash line in its source's rank, beside it",
       :aggregate_failures do
      svg = Sirena.render(capitals, notation: :plantuml)
      (city_x, city), (london_x, london) = corners(svg, "CapitalCity", "London")

      expect(london).to eq(city)
      expect(london_x).to be > city_x
    end

    it "puts a two-dash line's end one rank on, a three-dash line's two" do
      svg = Sirena.render(capitals, notation: :plantuml)
      ys = corners(svg, "NewYork", "CapitalCity", "Washington", "Berlin")
        .map(&:last)

      expect(ys.each_cons(2).map { |a, b| b > a }).to all(be(true))
    end

    it "keeps a box tied to another by a one-dash line right after it",
       :aggregate_failures do
      svg = render("object C\nobject B\nobject A\nA -right-> B\nB -right-> C")
      xs = corners(svg, "A", "B", "C").map(&:first)

      expect(xs).to eq(xs.sort)
      expect(xs.uniq.size).to eq(3)
    end

    it "keeps boxes tied to one box in their declared order after it" do
      svg = render("object Y\nobject X\nobject P\nP -right-> X\nP -right-> Y")
      xs = corners(svg, "P", "Y", "X").map(&:first)

      expect(xs).to eq(xs.sort)
    end

    it "lays a one-dash cycle out without looping" do
      svg = render("object A\nobject B\nA -right-> B\nB -right-> A")

      expect(corners(svg, "A", "B").size).to eq(2)
    end

    it "keeps a left or right word in one rank, an up or down a rank on",
       :aggregate_failures do
      same = corners(render("object A\nobject B\nA -right-> B"), "A", "B")
      next_rank = corners(render("object A\nobject B\nA -down-> B"), "A", "B")

      expect(same.map(&:last).uniq.size).to eq(1)
      expect(next_rank.map(&:last).uniq.size).to eq(2)
    end
  end

  describe "a link out of a map row" do
    let(:svg) { Sirena.render(capitals, notation: :plantuml) }

    def link_paths
      elements(svg, "path").map { |p| p.attributes["d"] }
    end

    it "is a spline" do
      expect(link_paths.grep(/ C /).size).to eq(4)
    end

    it "leaves from the side of its row" do
      uk = link_paths.find { |d| d.include?("C") }
      city = elements(svg, "rect").find { |r| r.attributes["height"].to_f > 80 }
      right = city.attributes["x"].to_f + city.attributes["width"].to_f

      expect(uk.split[1].to_f).to eq(right)
    end

    it "leaves from the left side when its target lies to the left" do
      svg = render("object X\nobject Y\nmap M {\n  a --> X\n  b --> Y\n}")
      city = elements(svg, "rect").find { |r| r.attributes["height"].to_f > 40 }
      starts = elements(svg, "path").map { |p| p.attributes["d"].split[1].to_f }

      expect(starts).to include(city.attributes["x"].to_f)
    end

    it "stays straight when it joins two whole boxes" do
      path = elements(render("object A\nobject B\nA --> B"), "path")
        .map { |p| p.attributes["d"] }

      expect(path.first).to match(/\AM [\d. ]+ L [\d. ]+\z/)
    end
  end

  describe "a plain object box" do
    it "rules off an empty second compartment below the title" do
      svg = render("object Solo")
      top = elements(svg, "rect").first.attributes["y"].to_f
      rule = elements(svg, "line").first.attributes["y1"].to_f

      expect(rule - top).to be_within(0.01).of(Sirena::Notation::PlantUMLData::Boxes::TableBox::ROW)
    end
  end
end
