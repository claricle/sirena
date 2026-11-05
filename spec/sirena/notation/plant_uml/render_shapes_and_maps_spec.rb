# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# Shapes and map boxes as the PlantUML JAR draws them: a map row's link has
# no diamond, a dotted name stands in packages, a map's key column fits its
# keys, a cloud is a run of small bumps, a package wears a tab, a component
# carries a small icon and a note points with a triangle.
RSpec.describe Sirena::Notation::PlantUML, "#render shapes and maps" do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.register(described_class) unless
      Sirena::Notation.ids.include?(described_class.id)
  end

  def render(body)
    svg = Sirena.render("@startuml\n#{body}\n@enduml\n", notation: :plantuml)
    REXML::Document.new(svg).root
  end

  def all(root, name)
    REXML::XPath.match(root, "//#{name}")
  end

  def bold_texts(root)
    all(root, "text").select { |t| t.attributes["font-weight"] == "bold" }
      .map { |t| t.texts.join }
  end

  def point_counts(root)
    all(root, "polygon").map { |p| p.attributes["points"].split.size }
  end

  describe "a map row's link" do
    it "draws only the three-point head of a plain arrow" do
      root = render("object London\nmap Capital {\n  UK *-> London\n}")

      expect(point_counts(root)).to eq([3])
    end
  end

  describe "a dotted object name" do
    let(:root) do
      render("map Kick.Off {\n}\nmap task.1 {\n  a => b\n}\n" \
             "Kick.Off --> task.1")
    end

    it "stands in a package of the leading names" do
      expect(bold_texts(root)).to include("Kick", "task")
    end

    it "keeps its own title" do
      expect(all(root, "text").map { |t| t.texts.join })
        .to include("Kick.Off", "task.1")
    end

    it "frames each package around its boxes" do
      frames = all(root, "rect").select { |r| r.attributes["fill"] == "none" }

      expect(frames.size).to eq(2)
    end

    it "nests the packages of a deeper name and of an undeclared end" do
      deep = render("object a.b.c\na.b.c --> x.y")

      expect(bold_texts(deep)).to contain_exactly("a", "b", "x")
    end

    it "keeps a name with an alias out of any package" do
      expect(bold_texts(render("object \"a.b\" as ab"))).to be_empty
    end
  end

  describe "a map's key column" do
    let(:root) do
      render("map users {\n  1 => Alice\n  22 => Bob and a long value\n}")
    end
    let(:split) do
      all(root, "line").find { |l| l.attributes["y1"] != l.attributes["y2"] }
    end

    it "is as wide as its keys, not half the box" do
      box = all(root, "rect").first

      expect(split.attributes["x1"].to_f - box.attributes["x"].to_f)
        .to be < box.attributes["width"].to_f / 3
    end

    it "centres the key of a row that only links out across the box" do
      key = all(render("object Z\nmap m {\n  UK *-> Z\n}"), "text")
        .find { |t| t.texts.join == "UK" }

      expect(key.attributes["text-anchor"]).to eq("middle")
    end
  end

  describe "a cloud" do
    let(:root) { render("cloud c1 as \"a\\ncloud\"") }

    it "is an outline of many small bumps" do
      expect(all(root, "path").first.attributes["d"].scan("Q").size)
        .to be > 20
    end

    it "is not an ellipse" do
      expect(all(root, "ellipse")).to be_empty
    end
  end

  describe "a package, folder and frame" do
    %w[package folder frame].each do |kind|
      it "puts the name of a #{kind} in a tab over its top left" do
        root = render("#{kind} \"Name\" {\n  [c]\n}")

        expect([point_counts(root), bold_texts(root)])
          .to eq([[5], ["Name"]])
      end
    end
  end

  describe "a component" do
    let(:box) { all(render("[Web]"), "rect").first }
    let(:icon) { all(render("[Web]"), "rect")[1] }

    it "is a rounded box" do
      expect(box.attributes["rx"]).to eq("2.5")
    end

    it "carries a small icon at its top right" do
      expect([icon.attributes["width"], icon.attributes["height"]])
        .to eq(%w[15.0 8.0])
    end

    it "has the icon's two tabs" do
      expect(all(render("[Web]"), "rect").size).to eq(4)
    end

    it "gives a component container the icon as well" do
      expect(all(render("component C {\n  [a]\n}"), "rect").size).to eq(8)
    end
  end

  describe "a note" do
    let(:root) { render("[a]\nnote right of [a] : hi") }

    it "points at its target with a pale triangle" do
      tail = all(root, "polygon").select do |p|
        p.attributes["fill"] == "#FEFFDD"
      end

      expect(tail.map { |p| p.attributes["points"].split.size }).to include(3)
    end

    it "draws no dashed line to its target" do
      dashed = all(root, "line").select { |l| l.attributes["stroke-dasharray"] }

      expect(dashed).to be_empty
    end
  end
end
