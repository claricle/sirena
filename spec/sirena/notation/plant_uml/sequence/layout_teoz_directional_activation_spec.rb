# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:sequence) { Sirena::Notation::PlantUML::Sequence }
  let(:label) { "abcdefghij" }

  context "with directional activation clearance" do
    let(:cases) do
      [0, 1, 2, 4].flat_map do |depth|
        [["A", "B", 0, depth, depth.positive? ? 5.0 : 0.0],
         ["B", "A", 0, depth, depth * 5.0],
         ["B", "A", 1, depth, (depth * 5.0) + 5.0]]
      end
    end
    let(:measured) do
      cases.map do |from, to, sender, receiver, _|
        body = ("activate #{from}\n" * sender) +
          ("activate #{to}\n" * receiver)
        source = "@startuml\n!pragma teoz true\nparticipant A\n" \
                 "participant B\n#{body}#{from} -> #{to}: #{label}\n@enduml"
        parsed = sequence.parse(source)
        lines = parsed.transform.new.call(parsed.diagram).lifelines
        lines.last.x1 - lines.first.x1
      end
    end
    let(:expected) do
      width = sequence::TextAdvances.width(label, font_size: 13)
      cases.map { |row| width + 24.0 + row.last }
    end

    it "reserves current bar interiors in both spatial directions" do
      expect(measured).to eq(expected)
    end
  end

  context "with activations after notes on the current tile" do
    let(:cases) { ["& note right of B: note", "note right of B: note"] }
    let(:starts) do
      cases.map do |note|
        source = "@startuml\n!pragma teoz true\nA -> B: #{label}\n" \
                 "#{note}\nactivate A\n@enduml"
        parsed = sequence.parse(source)
        scene = parsed.transform.new.call(parsed.diagram)
        start = scene.arrows.first.path[/M (\S+)/, 1].to_f
        start - scene.lifelines.first.x1
      end
    end

    it "looks through parallel notes and stops at ordinary notes" do
      expect(starts).to eq([5.0, 0.0])
    end
  end

  context "with inline activation changes and reordered participants" do
    let(:cases) do
      [["A\nparticipant B", "B -> A ++", "", 5.0],
       ["B\nparticipant A", "B -> A ++", "", 5.0],
       ["A\nparticipant B", "B -> A --", "activate B\n", 5.0],
       ["A\nparticipant B", "B -> A --++", "activate B\n", 10.0]]
    end
    let(:gaps) do
      cases.map do |participants, arrow, before, _|
        source = "@startuml\n!pragma teoz true\nparticipant #{participants}\n" \
                 "#{before}#{arrow}: #{label}\n@enduml"
        parsed = sequence.parse(source)
        lines = parsed.transform.new.call(parsed.diagram).lifelines
        lines.last.x1 - lines.first.x1
      end
    end
    let(:expected) do
      width = sequence::TextAdvances.width(label, font_size: 13)
      cases.map { |row| width + 24.0 + row.last }
    end

    it "uses tile activations and spatial order for inline changes" do
      expect(gaps).to eq(expected)
    end
  end
end
