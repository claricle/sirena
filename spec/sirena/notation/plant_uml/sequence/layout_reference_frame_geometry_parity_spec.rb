# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  def scene_of(*body)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(
      "@startuml\n#{body.join("\n")}\n@enduml\n",
    )
    parsed.transform.new.call(parsed.diagram)
  end

  it "uses pinned label width and side padding for a reference frame" do
    scene = scene_of("participant A", "participant B",
                     "ref over A, B: My Reference", "A -> B: hello")
    frame = scene.fragments.first
    centres = scene.heads.first(2).map { |head| head.x + (head.width / 2) }

    expect([frame.width, centres.last - centres.first])
      .to contain_exactly(be_within(0.0001).of(95.6484),
                          be_within(0.0001).of(67.6484))
  end

  it "keeps the fixed reference tab around a short single-target guard" do
    scene = scene_of("A -> B", "ref over A : r", "note top: x")
    frame = scene.fragments.first
    centres = scene.heads.first(2).map { |head| head.x + (head.width / 2) }

    expect([frame.width, centres.last - centres.first])
      .to contain_exactly(be_within(0.0001).of(63.916),
                          be_within(0.0001).of(43.958))
  end
end
