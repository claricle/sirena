# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence do
  include PlantUmlSequenceIrHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "hands layout the shared graph, not its private diagram" do
    parsed = described_class.parse(sequence_feature_source)

    expect(parsed.diagram).to be_a(Sirena::IR::Graph)
  end

  it "renders a sequence diagram through the shared graph" do
    svg = Sirena.render("@startuml\nA -> B : hi\n@enduml\n",
                        notation: :plantuml)

    expect(svg).to include("hi")
  end
end
