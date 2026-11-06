# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUMLData::Boxes::Ornaments,
               :aggregate_failures do
  include_context "with an isolated notation registry"

  before do
    [Sirena::Notation::PlantUML, Sirena::Notation::PlantUMLData].each do |n|
      Sirena::Notation.register(n) unless Sirena::Notation.ids.include?(n.id)
    end
  end

  def svg_of(cell)
    source = "@startyaml\nk: #{cell}\n@endyaml"
    REXML::Document.new(Sirena.render(source, notation: :plantuml_data))
  end

  def shapes(doc, name)
    doc.get_elements("//#{name}")
  end

  def value_text(doc)
    shapes(doc, "text").last
  end

  def words(element)
    REXML::XPath.match(element, ".//text()").map(&:value).join
  end

  def number(element, attribute)
    element.attributes[attribute].to_f
  end

  it "paints <back:..> as a rectangle under the text" do
    doc = svg_of("<back:orange>Orange")
    back = shapes(doc, "rect").find { |r| r.attributes["fill"] == "orange" }
    text = value_text(doc)

    expect(number(back, "x")).to be_within(0.01).of(number(text, "x"))
    expect(number(back, "y")).to be < number(text, "y")
  end

  it "draws <s:green> and <u:red> as their own coloured lines" do
    doc = svg_of("<s:green>cut <u:red>under")
    colours = shapes(doc, "line").map { |l| l.attributes["stroke"] }
    spans = shapes(doc, "tspan").map { |t| t.attributes["text-decoration"] }

    expect(colours).to include("green", "red")
    expect(spans.compact).to be_empty
  end

  it "keeps a plain <s> as a text decoration, not a drawn line" do
    doc = svg_of("<s>cut")

    expect(shapes(doc, "tspan").map { |t| t.attributes["text-decoration"] })
      .to include("line-through")
    expect(shapes(doc, "line").map { |l| l.attributes["stroke"] })
      .not_to include("green")
  end

  it "grows a row with its <size:..>" do
    plain = svg_of("big")
    sized = svg_of("<size:20>big")

    expect(number(sized.root, "height") - number(plain.root, "height"))
      .to be_within(0.01).of(7.07)
  end

  it "sinks the baseline of a cell with its <size:..>" do
    plain = value_text(svg_of("big"))
    sized = value_text(svg_of("<size:20>big"))

    expect(number(sized, "y") - number(plain, "y")).to be_within(0.01).of(5.8)
  end

  it "draws <&icon> as the Open Iconic outline scaled to the font" do
    doc = svg_of("go <&account-login>")
    glyph = shapes(doc, "path").find { |p| p.attributes["transform"] }

    expect(glyph.attributes["d"]).to start_with("M3 0v1h4v5h-4v1h5v-7h-5z")
    expect(glyph.attributes["transform"]).to include("scale(1.1667)")
    expect(words(value_text(doc))).not_to include("account-login")
  end

  it "leaves an icon name PlantUML does not ship as literal text" do
    doc = svg_of("<&no-such-icon>")

    expect(words(value_text(doc))).to include("<&no-such-icon>")
    expect(shapes(doc, "path").select { |p| p.attributes["transform"] })
      .to be_empty
  end

  it "holds an emoji's place with an outlined box and shows the rest" do
    doc = svg_of("<:calendar:> Calendar")
    boxes = shapes(doc, "rect").select { |r| r.attributes["fill"] == "none" }

    expect(boxes.map { |r| number(r, "width") }).to include(14.0)
    expect(words(value_text(doc))).to include("Calendar")
  end

  it "never fetches <img:..>: it prints PlantUML's `(Cannot decode)`" do
    doc = svg_of("<img:https://example.test/a.png>")

    expect(words(value_text(doc))).to eq("(Cannot decode)")
    expect(shapes(doc, "image")).to be_empty
  end

  it "makes room for `(Cannot decode)` in monospace advances" do
    boxes = Sirena::Notation::PlantUMLData::Boxes
    width = boxes::Text.width("<img:https://example.test/a.png>")

    expect(width).to be_within(0.001).of("(Cannot decode)".length * 14 * 0.602)
  end

  describe "label creole (not a data cell)" do
    let(:creole) { Sirena::Notation::PlantUML::Creole }

    it "still ignores <back:..> and keeps <&icon> literal" do
      runs = creole.parse("<back:red>a <&account-login>")

      expect(runs.map(&:text).join).to eq("a <&account-login>")
      expect(runs.map { |r| r.style.keys }.flatten).not_to include(:back)
    end

    it "still gives <s:green> a black line-through" do
      node = Sirena::Svg::Text.new
      creole.assign(node, "<s:green>x")

      expect(node.tspans.first.text_decoration).to eq("line-through")
    end
  end
end
