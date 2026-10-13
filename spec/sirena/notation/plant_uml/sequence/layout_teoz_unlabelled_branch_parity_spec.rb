# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:scenes) do
    ["", ": second"].map do |label|
      source = "@startuml\n!pragma teoz true\nalt first\nA -> B: first\n" \
               "else second\nB -> A#{label}\nend\n@enduml"
      parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
      parsed.transform.new.call(parsed.diagram)
    end
  end
  let(:geometry) do
    scenes.map do |scene|
      frame = scene.fragments.first
      shafts = scene.arrows.map do |arrow|
        arrow.path[/M \S+ (\S+)/, 1].to_f
      end
      [frame.y, frame.height, *shafts].map { |value| value.round(4) }
    end
  end
  let(:expected) do
    [[53.4883, 101.5762, 102.1094, 147.0645],
     [53.4883, 116.8867, 102.1094, 162.3750]]
  end

  it "matches pinned PlantUML 1.2026.6 alt frame and branch shaft positions" do
    expect(geometry).to eq(expected)
  end

  it "reserves one label row only when the else message has a label" do
    shifts = geometry.last.zip(geometry.first)
      .map { |labelled, unlabelled| (labelled - unlabelled).round(4) }

    expect(shifts).to eq([0.0, 15.3105, 0.0, 15.3105])
  end
end
