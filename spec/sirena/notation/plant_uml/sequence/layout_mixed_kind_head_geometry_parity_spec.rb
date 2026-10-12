# frozen_string_literal: true

require "nokogiri"
require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "sizes a plain participant to its label beside an actor" do
    source = <<~PLANTUML
      @startuml
      participant App
      actor OEM
      App -> OEM : hi
      @enduml
    PLANTUML
    document = Nokogiri::XML(
      Sirena.render(source, notation: :plantuml),
    ).remove_namespaces!
    rectangle = document.at_xpath(
      '//g[starts-with(@id,"participant-App-")]/rect',
    )

    expect(rectangle["width"].to_f).to eq(38.906)
  end
end
