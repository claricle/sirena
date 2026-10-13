# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:source) do
    <<~PLANTUML
      @startuml
      #{pragma}
      actor Author
      participant Build
      participant Sirena
      Author -> Build: Submit document
      loop Each diagram
        Build -> Sirena: Render source
        alt Source accepted
          Sirena --> Build: SVG diagram
        else #{guard}
          Sirena --> Build: #{message}
        end
      end
      @enduml
    PLANTUML
  end
  let(:pragma) { "" }
  let(:guard) { "Invalid source" }
  let(:message) { "Parse error" }
  let(:scene) do
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    parsed.transform.new.call(parsed.diagram)
  end

  [
    ["Invalid source", "Parse error"],
    ["Retry after validation", "Return a corrected document"],
    ["Rejected: <data> & names", "Error: <source> & details"],
  ].each do |heading, reply|
    context "with classic guard #{heading.inspect}" do
      let(:guard) { heading }
      let(:message) { reply }

      it "keeps the following message text below its guard heading" do
        heading = scene.fragments.first.texts.last
        message = scene.arrows.last.texts.first

        expect((message.y - heading.y).round(4)).to be >= 14.0
      end

      it "keeps the following return shaft below the guard text" do
        heading = scene.fragments.first.texts.last
        shaft_y = scene.arrows.last.path[/M \S+ (\S+)/, 1].to_f

        expect((shaft_y - heading.y).round(4)).to be >= 14.0
      end
    end
  end

  context "with an empty classic branch" do
    let(:guard) { "" }

    it "keeps the existing unlabelled branch cadence" do
      ys = scene.arrows.last(2).map do |arrow|
        arrow.path[/M \S+ (\S+)/, 1].to_f
      end

      expect((ys.last - ys.first).round(4)).to eq(31.3105)
    end
  end

  context "with Teoz branch headers" do
    let(:pragma) { "!pragma teoz true" }

    it "preserves the separate Teoz branch cadence" do
      ys = scene.arrows.last(2).map do |arrow|
        arrow.path[/M \S+ (\S+)/, 1].to_f
      end

      expect((ys.last - ys.first).round(4)).to eq(60.2656)
    end
  end
end
