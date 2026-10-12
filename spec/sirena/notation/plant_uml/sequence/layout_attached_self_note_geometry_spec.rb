# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:prefix) do
    <<~PLANTUML
      @startuml
      b -> a
      box "Box A"
        participant a
      endbox
      a <- a : msg
    PLANTUML
  end

  def lifeline_gap(source)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    scene = parsed.transform.new.call(parsed.diagram)
    scene.lifelines.map(&:x1).then { |left, right| right - left }
  end

  it "does not widen a neighbour gap for a note attached to a self-message" do
    note = "note left: a very very very very long attached note\n"

    expect(lifeline_gap("#{prefix}#{note}@enduml\n"))
      .to eq(lifeline_gap("#{prefix}@enduml\n"))
  end
end
