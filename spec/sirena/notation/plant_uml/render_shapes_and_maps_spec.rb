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
        .to be > 15
    end

    it "hugs what it holds, as the reference draws it" do
      root = render("cloud {\n  [Example 1]\n}")
      xs = all(root, "path").first.attributes["d"].scan(/[QM]?(\d+\.?\d*),/)
        .flatten.map(&:to_f)
      component = all(root, "rect").first.attributes["width"].to_f

      expect(xs.max - xs.min - component).to be_between(40, 55)
    end

    it "is only a little wider than the text of a lone cloud" do
      xs = all(root, "path").first.attributes["d"].scan(/[QM]?(\d+\.?\d*),/)
        .flatten.map(&:to_f)

      expect(xs.max - xs.min).to be < 80
    end

    it "is not an ellipse" do
      expect(all(root, "ellipse")).to be_empty
    end
  end

  describe "a package, folder and frame" do
    { "package" => 4, "folder" => 4, "frame" => 5 }.each do |kind, corners|
      it "puts the name of a #{kind} in a tab over its top left" do
        root = render("#{kind} \"Name\" {\n  [c]\n}")

        expect([point_counts(root), bold_texts(root)])
          .to eq([[corners], ["Name"]])
      end
    end

    it "leans the right edge of a package's tab down its whole height" do
      points = tab_points("package")

      expect([points[2][0] > points[1][0], points[2][1] - points[1][1]])
        .to eq([true, points[3][1] - points[0][1]])
    end

    it "makes a package's tab a line taller than a frame's" do
      heights = [tab_points("package"), tab_points("frame")].map do |pts|
        (pts.last[1] - pts.first[1]).round(2)
      end

      expect(heights).to eq([22.49, 20.0])
    end

    it "sets the name of a package lower in its tab than a frame's" do
      baselines = %w[package frame].map do |kind|
        all(render("#{kind} \"Name\" {\n  [c]\n}"), "text").first
          .attributes["y"].to_f.-(tab_points(kind).first[1]).round(2)
      end

      expect(baselines).to eq([15.5, 14.5])
    end

    it "cuts the lower right corner of a frame's tab" do
      points = tab_points("frame")

      expect([points[1][0] - points[2][0], points[3][0] < points[2][0]])
        .to eq([0.0, true])
    end

    def tab_points(kind)
      polygon = all(render("#{kind} \"Name\" {\n  [c]\n}"), "polygon").first
      polygon.attributes["points"].split.map { |pt| pt.split(",").map(&:to_f) }
    end
  end

  describe "a tab's padding" do
    def tab_geometry(kind, name)
      root = render("#{kind} \"#{name}\" {\n  [c]\n}")
      points = all(root, "polygon").first.attributes["points"].split
        .map { |pt| pt.split(",").map(&:to_f) }
      [points, all(root, "text").first.attributes["x"].to_f]
    end

    def bold_width(name)
      Sirena::TextMeasurement
        .measure_in(:dejavu_bold, name, font_size: 14)[:width]
    end

    # Measured on the JAR (1.2026.6): the name starts 4 right of a package's
    # or folder's tab and ends 2 short of its edge, a frame's 3 and 7.
    names = ["Some Group", "This is my folder", "Foo"]
    {
      "package" => [4, 2], "folder" => [4, 2], "frame" => [3, 7]
    }.each do |kind, (before, after)|
      names.each do |name|
        it "sets #{name} #{before} in and #{after} short in a #{kind}" do
          points, text_x = tab_geometry(kind, name)

          expect([text_x - points[0][0], points[1][0] - text_x -
            bold_width(name)].map { |gap| gap.round(2) })
            .to eq([before, after].map(&:to_f))
        end
      end
    end
  end

  describe "a cloud's room" do
    # The JAR's untitled cloud is 36.3 taller than what it holds; the bump
    # control points of ours reach 4 beyond the outline on each side.
    it "leaves the JAR's room around what an untitled cloud holds" do
      root = render("cloud {\n  [Example 1]\n}")
      held = all(root, "rect").find { |r| r.attributes["rx"] }
      ys = all(root, "path").first.attributes["d"].scan(/,(-?\d+\.?\d*)/)

      expect(ys.flatten.map(&:to_f).minmax.reverse.reduce(:-) -
        held.attributes["height"].to_f).to be_within(0.1).of(44.3)
    end

    it "gives a titled cloud its header and no extra height" do
      root = render("cloud \"Named\" {\n  [Example 1]\n}")
      held = all(root, "rect").find { |r| r.attributes["rx"] }
      ys = all(root, "path").first.attributes["d"].scan(/,(-?\d+\.?\d*)/)

      expect(ys.flatten.map(&:to_f).minmax.reverse.reduce(:-) -
        held.attributes["height"].to_f).to be_within(0.1).of(66.5)
    end

    it "keeps the header of an untitled package" do
      root = render("package {\n  [Example 1]\n}")
      frame = all(root, "rect").find { |r| r.attributes["fill"] == "none" }
      held = all(root, "rect").find { |r| r.attributes["fill"] == "#F1F1F1" }

      expect(frame.attributes["height"].to_f - held.attributes["height"].to_f)
        .to be_within(0.1).of(42)
    end

    it "hugs what it holds instead of doubling its size" do
      root = render("cloud {\n  [A]\n}")
      comp = all(root, "rect").first
      path = all(root, "path").first.attributes["d"]
      xs = path.scan(/[ML]?(-?\d+\.?\d*),/).flatten.map(&:to_f)

      expect(xs.max - xs.min - comp.attributes["width"].to_f).to be < 100
    end
  end

  describe "an archimate technology device" do
    it "carries the device icon, with its name below it" do
      root = render("archimate #Technology \"VPN\" as v <<technology-device>>")
      icon = all(root, "path").find { |p| p.attributes["transform"] }

      expect(icon.attributes["d"]).to start_with("M0.59,0")
    end

    it "stays a plain box for a type without an icon" do
      root = render("archimate #Technology \"VPN\" as v <<technology-node>>")

      expect(all(root, "path")).to be_empty
    end
  end

  describe "labelled links fanning from one node" do
    let(:label) { "a rather long label #{'x' * 20}" }
    let(:body) do
      Array.new(3) { |i| "[foo] --> [bar#{i}] : #{label}#{i}" }.join("\n")
    end
    let(:centres) do
      all(render(body), "rect").select { |r| r.attributes["width"].to_f > 40 }
        .map { |r| centre(r).round(1) }.uniq.sort
    end

    def centre(rect)
      rect.attributes["x"].to_f + (rect.attributes["width"].to_f / 2)
    end

    it "keeps their targets apart by the labels' width" do
      expect(centres.each_cons(2).map { |a, b| b - a }.min).to be > 150
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
        .to eq(%w[15.0 10.0])
    end

    it "draws the box with a hairline and the icon likewise" do
      rects = all(render("[Web]"), "rect")

      expect(rects.map { |r| r.attributes["stroke-width"] }.uniq).to eq(["0.5"])
    end

    it "keeps a container's frame at the plain line, its icon a hairline" do
      rects = all(render("component C {\n  [a]\n}"), "rect")

      expect(rects.map { |r| r.attributes["stroke-width"] }.first(5))
        .to eq(%w[1 0.5 0.5 0.5 0.5])
    end

    it "draws a port with a heavy line" do
      rects = all(render("component C {\n  portin p1\n  [a]\n}"), "rect")

      expect(rects.map { |r| r.attributes["stroke-width"] }).to include("1.5")
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

    it "is drawn with a hairline" do
      tail = all(root, "polygon").select do |p|
        p.attributes["fill"] == "#FEFFDD"
      end

      expect(tail.map { |p| p.attributes["stroke-width"] }.uniq).to eq(["0.5"])
    end

    it "draws no dashed line to its target" do
      dashed = all(root, "line").select { |l| l.attributes["stroke-dasharray"] }

      expect(dashed).to be_empty
    end
  end
end
