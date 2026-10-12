# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  def scene_of(*body)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(
      "@startuml\n#{body.join("\n")}\n@enduml\n",
    )
    parsed.transform.new.call(parsed.diagram)
  end

  def head_centres(scene)
    scene.heads.first(scene.heads.size / 2).to_h do |head|
      [head.id, head.x + (head.width / 2)]
    end
  end

  it "keeps the following participant clear of a nested self-message" do
    scene = scene_of("group test", "a -> b: 1", "c -> c: 2", "end",
                     "d -> d: next")
    centres = head_centres(scene)

    expect(centres.fetch("d") - centres.fetch("c")).to eq(50.0)
  end

  it "does not add nested clearance to a self-message before a fragment" do
    scene = scene_of("x -> x: start", "group test", "a -> b: 1",
                     "ref over b, c: a reference spanning b and c", "end",
                     "d -> d: next")
    centres = head_centres(scene)

    expect(centres.fetch("a") - centres.fetch("x")).to be < 50.0
  end
end
