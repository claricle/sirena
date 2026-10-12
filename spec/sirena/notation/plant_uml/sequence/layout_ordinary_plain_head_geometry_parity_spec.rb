# frozen_string_literal: true

require "nokogiri"
require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "uses intrinsic dimensions for an ordinary plain participant" do
    source = <<~PLANTUML
      @startuml
      participant A
      A -> A : hi
      @enduml
    PLANTUML
    document = Nokogiri::XML(
      Sirena.render(source, notation: :plantuml),
    ).remove_namespaces!
    rectangle = document.at_xpath(
      '//g[starts-with(@id,"participant-A-")]/rect',
    )

    expect(%w[width height].map { |name| rectangle[name].to_f })
      .to eq([23.338, 30.4883])
  end
end
