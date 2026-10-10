# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML do
  include PlantUmlIrHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  it "hands layout the shared graph, not its private diagram" do
    parsed = described_class.parse(feature_source)

    expect(parsed.diagram).to be_a(Sirena::IR::Graph)
  end

  it "renders a class diagram through the shared graph" do
    svg = Sirena.render(feature_source, notation: :plantuml)

    expect(svg).to include("class-Shape")
  end
end
