# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  def first_arrow_y(message)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(
      "@startuml\n#{message}\n@enduml\n",
    )
    arrow = parsed.transform.new.call(parsed.diagram).arrows.first

    arrow.path[/M \S+ (\S+)/, 1].to_f
  end

  it "uses the pinned initial gaps for classic messages" do
    actual = [first_arrow_y("A -> B"), first_arrow_y("A -> B: request")]

    expect(actual).to eq([67.7988, 82.7988])
  end
end
