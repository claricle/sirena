# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:dot_source) { plantuml("class A\nclass B\nA --> B") }
  let(:smetana_source) do
    plantuml("class C1\nclass C2\nC1 --> C2", smetana: true)
  end
  let(:mixed_length_source) { plantuml("class A\nclass Long\nA --> Long") }

  def plantuml(body, smetana: false)
    pragma = "!pragma layout smetana\n" if smetana
    "@startuml\n#{pragma}#{body}\n@enduml\n"
  end

  def class_widths(source)
    document = Nokogiri::XML(Sirena.render(source, notation: :plantuml))
    document.remove_namespaces!
    document.xpath("//g[starts-with(@id, 'class-')]/rect").map do |rect|
      rect["width"].to_f
    end
  end

  it "matches PlantUML's icon and title widths for plain empty classes" do
    expect(class_widths(dot_source)).to eq([41.5, 41.5])
  end

  it "uses the same intrinsic title width under Smetana" do
    expect(class_widths(smetana_source)).to eq([50.5, 50.5])
  end

  it "keeps the uniform-box layout when title lengths differ" do
    expect(class_widths(mixed_length_source)).to eq([57.6, 57.6])
  end
end
