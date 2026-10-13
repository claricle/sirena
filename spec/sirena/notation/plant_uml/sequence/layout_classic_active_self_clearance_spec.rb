# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:cases) do
    (0..3).map do |depth|
      clearance = depth.zero? ? 50.0 : 60.0 + (10 * depth)
      ["activate c\n" * depth, "c -> c : 2", clearance]
    end + [
      ["activate c\ndeactivate c\n", "c -> c : 2", 50.0],
      ["activate c\ndestroy c\n", "c -> c : 2", 50.0],
      ["", "c -> c ++ : 2", 50.0],
    ]
  end
  let(:gaps) do
    cases.map do |before, message, _|
      source = "@startuml\nx -> x : start\ngroup test\na -> b : 1\n" \
               "#{before}#{message}\nend\nd -> d : next\n@enduml\n"
      parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
      lines = parsed.transform.new.call(parsed.diagram).lifelines
      lines.last.x1 - lines[-2].x1
    end
  end

  it "uses the pinned activation depth before each nested self message" do
    expect(gaps).to eq(cases.map(&:last))
  end
end
