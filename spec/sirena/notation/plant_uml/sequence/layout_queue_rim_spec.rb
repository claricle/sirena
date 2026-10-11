# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:rim) do
    source = "@startuml\nqueue q\n@enduml\n"
    result = Sirena::Notation::PlantUML::Sequence.parse(source)
    scene = result.transform.new.call(result.diagram)
    svg = result.renderer.new.render(scene).to_xml
    svg.scan(/d="([^"]*)"/).flatten.find { |data| data.count("C") == 2 }
  end
  let(:cubics) { rim.split(/(?=[MLC])/).select { _1.start_with?("C") } }

  it "draws each queue rim curve with three point pairs" do
    expect(cubics.map { |curve| curve[1..].split.size }).to eq([6, 6])
  end

  it "ends the queue rim on the box corner, as PlantUML does" do
    expect(cubics.last.split.last(4).each_slice(2).to_a.uniq.size).to eq(1)
  end
end
