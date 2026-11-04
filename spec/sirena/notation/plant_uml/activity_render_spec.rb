# frozen_string_literal: true

require "spec_helper"
require_relative "activity/activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity do
  include ActivityHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "renders valid SVG with the action text", :aggregate_failures do
    svg = render("start\n:Hello world;\nstop")

    expect(svg_root(svg).name).to eq("svg")
    expect(svg_texts(svg)).to include("Hello world")
  end

  it "draws one text element per label line" do
    svg = render(":one\ntwo;")

    expect(svg_texts(svg)).to include("one", "two")
  end

  it "draws edge labels and decision conditions" do
    svg = render("if (ready?) then (yes)\n:go;\nelse (no)\n:wait;\nendif")

    expect(svg_texts(svg)).to include("ready?", "yes", "no", "go", "wait")
  end

  it "draws an arrow head per edge" do
    svg = render("start\n:a;\nstop")

    expect(svg.scan("<polygon").size).to eq(2)
  end

  it "dashes a dashed arrow and fills a coloured action" do
    svg = render(":a;\n-[#green,dashed]->\n#pink:b;")

    expect(svg).to include('stroke="green"', 'stroke-dasharray="7,5"',
                           'fill="pink"')
  end

  it "renders legacy syntax" do
    svg = render(%((*) --> "One"\n--> (*)))

    expect(svg_texts(svg)).to include("One")
  end

  it "is byte-identical for the same source" do
    source = "start\nwhile (x?)\n:a;\nendwhile\nstop"

    first = render(source)

    expect(render(source)).to eq(first)
  end

  it "is reported as an activity diagram", :aggregate_failures do
    parsed = Sirena::Notation::PlantUML.parse("@startuml\nstart\nstop\n@enduml")

    expect(parsed.type).to eq(:activity_diagram)
    expect(Sirena::Notation::PlantUML.types).to include(:activity_diagram)
  end

  it "leaves sequence diagrams to the sequence notation" do
    source = "@startuml\nAlice -> Bob: hi\n@enduml"
    parsed = Sirena::Notation::PlantUML.parse(source)

    expect(parsed.type).to eq(:sequence_diagram)
  end

  it "leaves class diagrams to the class notation" do
    source = "@startuml\nclass A\nA --> B\n@enduml"
    parsed = Sirena::Notation::PlantUML.parse(source)

    expect(parsed.type).to eq(:class_diagram)
  end
end
