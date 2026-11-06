# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"
  include DejaVuText

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def padded(text, padding)
    (dejavu(text, size: 14) + padding).round(4)
  end

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
    expected = %w[A B C].to_h { |name| [name, [padded(name, 6.0), 42.4883]] }

    expect(dimensions(id, expected.keys)).to eq(expected)
  end

  it "uses compact chrome for member classes when circles are hidden" do
    id = "resources.vega.nonreg.group2903.reported_case--fd42e1abb616"
    expected = { "Respuesta" => [padded("fecha: Date", 12.0), 58.9766],
                 "Opcion" => [padded("texto: String", 12.0), 58.9766],
                 "Voto" => [padded("getOpcion(): Opcion", 12.0), 58.9766] }

    expect(dimensions(id, expected.keys)).to eq(expected)
  end
end
