# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Timing::Layout,
               :aggregate_failures do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.register(Sirena::Notation::PlantUML) unless
      Sirena::Notation.ids.include?(Sirena::Notation::PlantUML.id)
  end

  let(:doc) do
    source = "@startuml\nbinary \"B\" as B\nanalog \"A\" as A\n@0\nB is low\n" \
             "A is 0\n@100\nB is high\nA is 3\n@enduml"
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end

  def strokes(doc)
    REXML::XPath.match(doc, "//path").map do |p|
      [p.attributes["stroke"], p.attributes["stroke-width"]]
    end
  end

  it "draws a digital signal in PlantUML's dark green at 1.5" do
    expect(strokes(doc)).to include(["#006400", "1.5"])
    expect(strokes(doc).map(&:first)).not_to include("#007900")
  end

  it "draws an analog line thin and grey" do
    expect(strokes(doc)).to include(["#333333", "0.5"])
  end

  it "sets a lane's name in 14px bold grey" do
    name = REXML::XPath.match(doc, "//text").find { |t| t.text == "B" }

    expect([name.attributes["font-size"], name.attributes["fill"],
            name.attributes["font-weight"]]).to eq(%w[14 #333333 bold])
  end
end
