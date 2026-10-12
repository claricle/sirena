# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  subject(:participant_gap) do
    parsed = Sirena::Notation::PlantUML::Sequence.parse(
      "@startuml\n!pragma teoz true\n#{body.join("\n")}\n@enduml\n",
    )
    heads = parsed.transform.new.call(parsed.diagram).heads
    centres = heads.to_h { |head| [head.id, head.x + (head.width / 2)] }
    (centres.fetch("right") - centres.fetch("left")).round(1)
  end

  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  context "with short labels" do
    let(:body) do
      ['participant "x" as left', 'participant "y" as right',
       "left -> left: other", "right -> right: next"]
    end

    it "keeps self-message loops clear" do
      expect(participant_gap).to eq(53.0)
    end
  end

  context "with a long label" do
    let(:body) do
      ["left -> left: test which is very very long", "right -> right: next"]
    end

    it "fits the self-message label at its sans width" do
      expect(participant_gap).to eq(185.2)
    end
  end
end
