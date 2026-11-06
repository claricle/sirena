# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(described_class)
  end

  def document(body)
    REXML::Document.new(
      Sirena.render("@startuml\n#{body}\n@enduml\n", notation: :plantuml),
    )
  end

  def attribute(element, name)
    element.attributes[name].to_f
  end

  def offsets(svg)
    box = REXML::XPath.first(svg, "//rect[@height='48']")
    spot = REXML::XPath.first(svg, "//circle")
    rules = REXML::XPath.match(svg, "//line").first(2)
    [attribute(spot, "cx") - attribute(box, "x"),
     rules.map { |line| attribute(line, "y1") - attribute(box, "y") }]
  end

  it "draws an empty class 48 high with its spot and two compartment rules" do
    expect(offsets(document("class Class\nobject Object")))
      .to eq([15.0, [32.0, 40.0]])
  end

  it "draws an empty map as its title alone, one row high" do
    svg = document("map Kick.Off {\n}\nobject Other")
    box = REXML::XPath.first(svg, "//rect[@height='20.4883']")

    expect([box.nil?, REXML::XPath.match(svg, "//line").size]).to eq([false, 1])
  end
end
