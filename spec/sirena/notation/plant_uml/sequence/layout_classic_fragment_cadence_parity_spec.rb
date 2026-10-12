# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:source) do
    <<~PLANTUML
      @startuml
      alt dummy
      alt foo
      Bob->Alice : hello
      else
      Bob<-Alice : hello2
      end
      note right: Some explication on foo.
      else
      Bob<-Alice : hello3
      end
      note right: Some explication on dummy.
      Alice->John_smith : hello
      Alice->An_other_actor : hello
      @enduml
    PLANTUML
  end

  it "uses the pinned classic branch and fragment-close cadence" do
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    arrows = parsed.transform.new.call(parsed.diagram).arrows
    ys = arrows.map { |arrow| arrow.path[/M \S+ (\S+)/, 1].to_f }

    expect(ys.each_cons(2).map { |first, second| (second - first).round(4) })
      .to eq([31.3105, 38.3105, 36.3105, 29.3105])
  end
end
