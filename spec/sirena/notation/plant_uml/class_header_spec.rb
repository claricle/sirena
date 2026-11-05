# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::ClassHeader do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  let(:body) { "class C1\nabstract class A1\ninterface I1\nenum E1\n" }
  let(:source) { "@startuml\n#{body}annotation N1\n@enduml\n" }
  let(:document) do
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end

  def group(id)
    REXML::XPath.first(document, "//g[@id='class-#{id}']")
  end

  def circle(id)
    REXML::XPath.first(group(id), "circle")
  end

  def style_of(id)
    attributes_of(REXML::XPath.first(group(id), "text[1]"), "font-weight",
                  "font-style")
  end

  def attributes_of(element, *names)
    names.map { |name| element.attributes[name] }
  end

  def name_text(id)
    REXML::XPath.first(group(id), "text[1]")
  end

  # PlantUML 1.2026.6 fills a class spot with these colours.
  {
    "C1" => "#ADD1B2", "A1" => "#A9DCDF", "I1" => "#B4A7E5",
    "E1" => "#EB937F", "N1" => "#E3664A"
  }.each do |name, fill|
    it "draws #{name} with a #{fill} spot of radius 11 and a black letter" do
      letter = REXML::XPath.first(group(name), "path")

      expect([attributes_of(circle(name), "fill", "r"),
              letter.attributes["fill"]])
        .to eq([[fill, "11.0"], "#000000"])
    end
  end

  it "sets the name to the right of its spot, 14 pixels from its centre" do
    spot_x = circle("C1").attributes["cx"].to_f
    name = name_text("C1").attributes

    expect([name["text-anchor"], name["x"].to_f - spot_x])
      .to match(["start", be_within(0.01).of(14.0)])
  end

  it "centres the spot at 5.291 above the name's baseline" do
    baseline = name_text("C1").attributes["y"].to_f

    expect(circle("C1").attributes["cy"].to_f)
      .to be_within(0.01).of(baseline - 5.291)
  end

  it "draws names plain, italic only for abstract classes and interfaces" do
    expect(%w[C1 A1 I1 E1 N1].to_h { |name| [name, style_of(name)] }).to eq(
      "C1" => [nil, nil], "A1" => [nil, "italic"], "I1" => [nil, "italic"],
      "E1" => [nil, nil], "N1" => [nil, nil]
    )
  end

  it "leaves a class without a spot under `hide circle`" do
    hidden = REXML::Document.new(
      Sirena.render("@startuml\nhide circle\nclass C1\n@enduml\n",
                    notation: :plantuml),
    )

    expect(REXML::XPath.match(hidden, "//circle")).to be_empty
  end

  it "rules the two empty compartments of a member-less class" do
    rules = REXML::XPath.match(group("C1"), "line")
    top = REXML::XPath.first(group("C1"), "rect").attributes["y"].to_f

    expect(rules.map { |line| line.attributes["y1"].to_f - top })
      .to eq([32.0, 40.0])
  end

  it "draws compartment rules a hairline thick and inset by one pixel" do
    box = REXML::XPath.first(group("C1"), "rect").attributes
    rule = REXML::XPath.first(group("C1"), "line").attributes

    expect([rule["stroke-width"], rule["x1"].to_f - box["x"].to_f,
            box["x"].to_f + box["width"].to_f - rule["x2"].to_f])
      .to eq(["0.5", 1.0, 1.0])
  end

  it "draws members in the sans-serif face the reference uses" do
    svg = Sirena.render("@startuml\nclass D {\n  String data\n}\n@enduml\n",
                        notation: :plantuml)

    expect(svg).not_to include("monospace")
  end
end
