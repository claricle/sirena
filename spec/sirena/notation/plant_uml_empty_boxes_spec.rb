# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe "PlantUML empty boxes in an object diagram" do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  def document(body)
    REXML::Document.new(
      Sirena.render("@startuml\n#{body}\n@enduml\n", notation: :plantuml),
    )
  end

  def attribute(element, name)
    element.attributes[name].to_f
  end

  it "draws an empty class 48 high with its spot and two compartment rules" do
    svg = document("class Class\nobject Object")
    box = REXML::XPath.first(svg, "//rect[@height='48']")
    rules = REXML::XPath.match(svg, "//line").map { |line| attribute(line, "y1") }
    spot = REXML::XPath.first(svg, "//circle")

    expect([attribute(spot, "cx") - attribute(box, "x"),
            rules.first(2).map { |y| y - attribute(box, "y") }])
      .to eq([15.0, [32.0, 40.0]])
  end

  it "draws an empty map as its title alone, one row high" do
    svg = document("map Kick.Off {\n}\nobject Other")
    box = REXML::XPath.first(svg, "//rect[@height='20.4883']")

    expect([box.nil?, REXML::XPath.match(svg, "//line").size]).to eq([false, 1])
  end
end
