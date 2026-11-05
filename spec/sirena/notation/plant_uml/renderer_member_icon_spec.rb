# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"
Sirena::Notation.send(:entries).delete(:plantuml)

# Geometry below is measured from PlantUML 1.2026.6 (the pinned reference).
RSpec.describe Sirena::Notation::PlantUML::Renderer do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:svg) do
    Sirena.render("@startuml\nclass Dummy {\n  -f1\n  #f2\n  ~f3\n  +f4\n  " \
                  "-m1()\n  #m2()\n  ~m3()\n  +m4()\n}\n@enduml\n",
                  notation: :plantuml)
  end
  let(:document) { REXML::Document.new(svg) }

  def modifiers
    REXML::XPath.match(document, "//g[@data-visibility-modifier]")
      .map { |group| group.attributes["data-visibility-modifier"] }
  end

  def icon(modifier)
    REXML::XPath.first(
      document, "//g[@data-visibility-modifier='#{modifier}']/*"
    )
  end

  it "marks each icon with its member's visibility and kind" do
    expect(modifiers).to eq(
      %w[PRIVATE_FIELD PROTECTED_FIELD PACKAGE_PRIVATE_FIELD PUBLIC_FIELD
         PRIVATE_METHOD PROTECTED_METHOD PACKAGE_PRIVATE_METHOD PUBLIC_METHOD],
    )
  end

  it "draws a field's icon hollow in the visibility's colour" do
    hollow = icon("PRIVATE_FIELD")

    expect([hollow.name, hollow.attributes["fill"],
            hollow.attributes["stroke"]]).to eq(%w[rect none #C82930])
  end

  it "fills a method's icon" do
    expect([icon("PRIVATE_METHOD").attributes["fill"],
            icon("PUBLIC_METHOD").attributes["fill"],
            icon("PROTECTED_METHOD").attributes["fill"],
            icon("PACKAGE_PRIVATE_METHOD").attributes["fill"]])
      .to eq(%w[#F24D5C #84BE84 #FFFF44 #4177AF])
  end

  it "draws the circle, diamond and triangle at PlantUML's size" do
    corners = %w[PROTECTED_FIELD PACKAGE_PRIVATE_FIELD].map do |modifier|
      icon(modifier).attributes["points"].split.size
    end

    expect([icon("PUBLIC_FIELD").attributes["r"], *corners])
      .to eq(["3.0", 4, 3])
  end
end
