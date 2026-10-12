# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:source) do
    "@startuml\na -> b\nreturn\na -> b : request\n" \
      "return response\n@enduml\n"
  end
  let(:arrow_ys) do
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    arrows = parsed.transform.new.call(parsed.diagram).arrows
    arrows.map { |arrow| arrow.path[/M \S+ (\S+)/, 1].to_f }
  end

  it "uses the pinned row before a classic unlabelled message" do
    gaps = arrow_ys.each_cons(2).map do |first, second|
      (second - first).round(4)
    end

    expect(gaps).to eq([14.0, 29.3105, 29.3105])
  end
end
