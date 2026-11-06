# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# The jar draws a class diagram 7 from the top and left edge and leaves 14
# after the last box (its 7 margin plus the 7 the canvas adds); the numbers
# come from plantuml 1.2026.6 on a lone class and a chain of two.
RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def document(*lines)
    source = ["@startuml", *lines, "@enduml"].join("\n")
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end

  def box_rect(doc, name)
    REXML::XPath.first(doc, "//g[@id='class-#{name}']/rect").attributes
  end

  def canvas(doc)
    root = doc.root.attributes
    [root["width"].to_f, root["height"].to_f]
  end

  context "with a lone class" do
    let(:doc) { document("class A") }

    it "starts the box 7 from the top left corner" do
      rect = box_rect(doc, "A")

      expect([rect["x"].to_f, rect["y"].to_f]).to eq([7.0, 7.0])
    end

    it "leaves 14 after the box on both axes" do
      rect = box_rect(doc, "A")
      width, height = canvas(doc)

      expect([width - rect["x"].to_f - rect["width"].to_f,
              height - rect["y"].to_f - rect["height"].to_f])
        .to eq([14.0, 14.0])
    end
  end

  context "with a hierarchy" do
    let(:doc) { document("class A", "class B", "A <|-- B") }

    it "starts the top box 7 from the top and leaves 14 below the last" do
      bottom = box_rect(doc, "B")
      below = canvas(doc).last - bottom["y"].to_f - bottom["height"].to_f

      expect([box_rect(doc, "A")["y"].to_f, below]).to eq([7.0, 14.0])
    end
  end

  context "with a package frame" do
    let(:doc) { document("package p {", "class A", "}") }

    it "keeps the frame's symmetric side room" do
      rect = box_rect(doc, "A")
      width = canvas(doc).first

      expect(width - rect["x"].to_f - rect["width"].to_f)
        .to be_within(0.001).of(rect["x"].to_f)
    end
  end
end
