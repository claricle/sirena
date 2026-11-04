# frozen_string_literal: true

require "spec_helper"
require_relative "plant_uml_salt/salt_helpers"

# Separators, headings, open droplists, text decoration and the canvas, as
# PlantUML 1.2026.6 draws them. Heights and offsets were read off its SVG;
# text widths are the DejaVu Sans advances the layout uses.
RSpec.describe Sirena::Notation::PlantUMLSalt do
  include SaltHelpers

  def render(body)
    REXML::Document.new(Sirena.render("@startsalt\n{\n#{body}\n}\n@endsalt"))
  end

  def numbers(element, *names)
    names.map { |name| element.attributes[name].to_f.round(2) }
  end

  def width_of(text, face = :dejavu, size: 12)
    Sirena::TextMeasurement.measure_in(face, text, font_size: size)[:width]
  end

  def attrs(element, *names)
    names.map { |name| element.attributes[name] }
  end

  def lines(doc)
    drawn(doc, "line")
  end

  def ys(doc, name = "text", key = "y")
    drawn(doc, name).map { |e| e.attributes[key].to_f.round(2) }
  end

  describe "separator rows" do
    {
      ".." => [["#AAAAAA", "1", "1,2", 25.63]],
      "==" => [["#AAAAAA", "1", nil, 24.63], ["#AAAAAA", "1", nil, 26.63]],
      "--" => [["#AAAAAA", "1", nil, 25.63]],
      "~~" => [["#AAAAAA", "1.5", nil, 25.63]],
    }.each do |mark, strokes|
      it "draws #{mark} as grey rules in the gap between two rows" do
        found = lines(render("a\n#{mark}\nb")).map do |line|
          attrs(line, "stroke", "stroke-width", "stroke-dasharray", "y1")
            .tap { |row| row[3] = row[3].to_f.round(2) }
        end

        expect(found).to eq(strokes)
      end
    end

    it "makes a separator row six high" do
      expect(ys(render("a\n..\nb"))).to eq([17.6, 41.73])
    end

    it "stretches a rule over the widest cell, a pixel past it" do
      rule = lines(render("abc\n--\nab")).first

      expect(numbers(rule, "x1", "x2"))
        .to eq([6.0, (6 + width_of("abc") + 1).round(2)])
    end

    it "drops a title closed by the same mark" do
      expect(render("a\n.. note ..\nb").get_elements("//text").map(&:text))
        .to eq(%w[a b])
    end

    it "draws no rule for a rule line inside a tree" do
      tree = Sirena.render("@startsalt\n{T\n+ a\n--\n}\n@endsalt")

      expect(REXML::Document.new(tree).get_elements("//line")
        .map { |l| l.attributes["stroke"] }).not_to include("#AAAAAA")
    end

    it "sets a rule line inside a tree as text" do
      tree = Sirena.render("@startsalt\n{T\n+ a\n--\n}\n@endsalt")

      expect(svg_texts(tree)).to include("--")
    end
  end

  describe "== Title headings" do
    let(:doc) { render("== Title\nb") }

    it "sets the title bold at fourteen pixels", :aggregate_failures do
      title = drawn(doc, "text").first

      expect(title.text).to eq("Title")
      expect(attrs(title, "font-size", "font-weight"))
        .to eq(%w[14 bold])
    end

    it "measures the title in the bold face at its own size" do
      expect(drawn(doc, "text").first.attributes["textLength"].to_f)
        .to be_within(0.001).of(width_of("Title", :dejavu_bold, size: 14))
    end

    it "makes the row a fourteenth taller and drops the baseline",
       :aggregate_failures do
      expect(ys(doc)).to eq([19.54, 36.09])
      expect(doc.root.attributes["viewBox"]).to eq("0 0 48 45")
    end

    it "keeps the cells after a heading" do
      texts = render("== Head | more\nb").get_elements("//text").map(&:text)

      expect(texts).to eq(%w[Head more b])
    end
  end

  describe "droplist choices" do
    let(:doc) { render("^open^x^yy^") }

    it "draws the choices as an open box below the widget" do
      box = drawn(doc, "rect").last

      expect(numbers(box, "x", "y", "width", "height"))
        .to eq([6.0, 23.13, 46.0, 27.27])
    end

    it "sets one choice a line, in order", :aggregate_failures do
      expect(svg_texts(doc.to_s)).to eq(%w[open x yy])
      expect(ys(doc)).to eq([19.6, 34.73, 48.87])
    end

    it "grows the canvas to hold the box" do
      expect(doc.root.attributes["viewBox"]).to eq("0 0 61 51")
    end

    it "widens the box to the widest choice" do
      wide = render("^a^a much longer choice^")
      box = drawn(wide, "rect").last

      expect(box.attributes["width"].to_f)
        .to be_within(0.001).of(width_of("a much longer choice") - 1)
    end

    it "draws no box for a droplist without choices" do
      expect(drawn(render("^open^"), "rect").size).to eq(1)
    end
  end

  describe "text decoration" do
    let(:doc) { render("<u>under</u> <s>strike</s> <u><s>both</s></u> plain") }
    let(:found) do
      drawn(doc, "text").to_h { |t| [t.text, t.attributes["text-decoration"]] }
    end

    it "sets underline and strike as SVG text-decoration" do
      expect(found.values_at("under", "strike", "both", "plain"))
        .to eq(["underline", "line-through", "underline line-through", nil])
    end

    it "draws no separate line for a decoration" do
      expect(lines(doc)).to be_empty
    end
  end

  describe "text length" do
    it "fixes every text to the width the layout measured",
       :aggregate_failures do
      text = drawn(render("Hello World"), "text").first

      expect(text.attributes["textLength"].to_f)
        .to be_within(0.0001).of(width_of("Hello World"))
      expect(text.attributes["lengthAdjust"]).to eq("spacing")
    end

    it "measures bold text in the bold face" do
      text = drawn(render("<b>Hello World</b>"), "text").first

      expect(text.attributes["textLength"].to_f)
        .to be_within(0.0001).of(width_of("Hello World", :dejavu_bold))
    end

    it "leaves leading spaces out of the length and into x",
       :aggregate_failures do
      text = drawn(render("<b>a</b>  b"), "text").last
      lead = width_of("a", :dejavu_bold) + width_of("  ")

      expect(numbers(text, "x", "textLength"))
        .to eq([(6 + lead).round(2), width_of("b").round(2)])
    end
  end

  describe "the canvas" do
    let(:doc) { render("a") }
    let(:ground) { doc.get_elements("//rect").first }

    it "is a white rectangle behind the diagram, the size of the viewBox",
       :aggregate_failures do
      expect(attrs(ground, "fill", "stroke", "stroke-width"))
        .to eq(%w[#FFFFFF none 0.0])
      expect(numbers(ground, "x", "y", "width", "height"))
        .to eq([0.0, 0.0, 20.0, 27.0])
      expect(doc.root.attributes["viewBox"]).to eq("0 0 20 27")
    end

    it "is the first element drawn" do
      expect(doc.get_elements("//svg/*").first).to eq(ground)
    end
  end

  describe "rows ending in a closing brace" do
    it "closes the block the row ends" do
      xs = render("{ a\n+ World }\nz").get_elements("//text")
        .map { |t| t.attributes["x"].to_f }

      expect(xs).to eq([7.0, 7.0, 6.0])
    end

    it "leaves the block open for a row that does not end in one" do
      xs = render("{ a\n+ World\nz").get_elements("//text")
        .map { |t| t.attributes["x"].to_f }

      expect(xs).to eq([7.0, 7.0, 7.0])
    end
  end

  describe "empty cells" do
    it "ignores a leading bar" do
      expect(ys(render("| c | d"))).to eq(ys(render("c | d")))
    end

    it "gives a lone dot the width of a dot", :aggregate_failures do
      doc = render("a | b\n. | e")
      xs = drawn(doc, "text").map { |t| t.attributes["x"].to_f.round(2) }

      expect(xs[1]).to eq((6 + width_of("a") + 2).round(2))
      expect(xs.last).to eq(xs[1])
    end

    it "sizes the column by the widest of a dot and its neighbour" do
      wide = render("ab | b\n. | e")
      xs = drawn(wide, "text").map { |t| t.attributes["x"].to_f.round(2) }

      expect(xs[1]).to eq((6 + width_of("ab") + 2).round(2))
    end
  end

  describe "what a widget reaches past its column" do
    it "counts a button's extra pixel toward the canvas" do
      expect(render("[OK]").root.attributes["viewBox"]).to eq("0 0 40 36")
    end

    it "lets the next column start where the button's cell ends",
       :aggregate_failures do
      doc = render("[OK] | z")

      expect(numbers(drawn(doc, "text").last, "x")).to eq([34.31])
      expect(doc.root.attributes["viewBox"]).to eq("0 0 47 36")
    end

    it "adds nothing when a wider cell holds the column" do
      expect(render("zzzzzzzzzzzzzzzzzz\n[OK]").root.attributes["viewBox"])
        .to eq("0 0 126 52")
    end
  end

  describe "the {T+ frame" do
    let(:doc) { Sirena.render("@startsalt\n{T+\n+ a\n++ b\n}\n@endsalt") }
    let(:frame) do
      REXML::Document.new(doc).get_elements("//line").select do |l|
        l.attributes["stroke"] == "#888888" &&
          [l.attributes["x1"], l.attributes["y1"]].map(&:to_f).include?(5.0)
      end
    end

    it "is four grey lines: top, bottom, left and right" do
      expect(frame.map { |l| numbers(l, "x1", "y1", "x2", "y2") }).to eq(
        [[5.0, 5.0, 37.62, 5.0], [5.0, 33.27, 37.62, 33.27],
         [5.0, 5.0, 5.0, 33.27], [37.62, 5.0, 37.62, 33.27]],
      )
    end

    it "draws no rectangle for the frame" do
      grey = REXML::Document.new(doc).get_elements("//rect")
        .select { |r| r.attributes["stroke"] == "#888888" }

      expect(grey.map { |r| numbers(r, "width") }).to eq([[2.0]])
    end
  end
end
