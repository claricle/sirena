# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def dimensions(id, names)
    source = File.read("spec/plantuml/class/#{id}.puml")
    document = Nokogiri::XML(Sirena.render(source, notation: :plantuml))
    document.remove_namespaces!
    names.to_h do |name|
      rectangle = document.at_xpath("//g[@id='class-#{name}']/rect")
      values = [rectangle["width"], rectangle["height"]]
      [name, values.map { |value| value.to_f.round(4) }]
    end
  end

  it "uses compact chrome for empty classes when circles are hidden" do
    id = "resources.vega.nonreg.group2903.nodesep_ranksep--7c073f601760"
    expected = { "A" => [15.6592, 42.4883],
                 "B" => [14.0527, 42.4883],
                 "C" => [15.6865, 42.4883] }

    expect(dimensions(id, expected.keys)).to eq(expected)
  end

  it "uses compact chrome for member classes when circles are hidden" do
    id = "resources.vega.nonreg.group2903.reported_case--fd42e1abb616"
    expected = { "Respuesta" => [88.6514, 58.9766],
                 "Opcion" => [96.2871, 58.9766],
                 "Voto" => [148.1172, 58.9766] }

    expect(dimensions(id, expected.keys)).to eq(expected)
  end
end
