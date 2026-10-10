# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Renderer do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "paints a note with the hex colour it was given" do
    source = "@startuml\nclass A\nnote right of A #FFAA00 : hi\n@enduml\n"

    expect(Sirena.render(source, notation: :plantuml)).to include("#FFAA00")
  end
end
