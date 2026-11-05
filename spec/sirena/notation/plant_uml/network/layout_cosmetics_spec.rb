# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Network::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:svg) do
    Sirena::Engine.new.render(<<~PUML, notation: :plantuml)
      @startuml
      nwdiag {
        network dmz {
          web01;
          db01 [shape = database];
        }
      }
      @enduml
    PUML
  end

  it "paints a bar with no colour PlantUML's lavender" do
    expect(svg).to include('fill="#E2E2F0"')
  end

  it "draws a database as a rounded body and the front edge of its lid",
     :aggregate_failures do
    expect(svg).not_to include("<ellipse")
    expect(svg).to match(/<path[^>]*d="M[^"]*Q[^"]*Z/i)
    expect(svg.scan(/<path[^>]*d="M[^"]*Q/).size).to be >= 2
  end
end
