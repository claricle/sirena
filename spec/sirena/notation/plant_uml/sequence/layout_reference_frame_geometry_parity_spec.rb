# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include DejaVuText

  def scene_of(*body)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(
      "@startuml\n#{body.join("\n")}\n@enduml\n",
    )
    parsed.transform.new.call(parsed.diagram)
  end

  def frame_width_and_spread(*body)
    scene = scene_of(*body)
    centres = scene.heads.first(2).map { |head| head.x + (head.width / 2) }
    [scene.fragments.first.width, centres.last - centres.first]
  end

  def reference_frame_and_spread
    frame = dejavu("My Reference", size: 12) + 18.0
    [frame, frame - 28.0].map { |width| be_within(1e-9).of(width) }
  end

  it "uses pinned label width and side padding for a reference frame" do
    measured = frame_width_and_spread("participant A", "participant B",
                                      "ref over A, B: My Reference",
                                      "A -> B: hello")

    expect(measured).to match_array(reference_frame_and_spread)
  end

  it "keeps the fixed reference tab around a short single-target guard" do
    measured = frame_width_and_spread("A -> B", "ref over A : r",
                                      "note top: x")

    expect(measured).to contain_exactly(be_within(0.0001).of(63.916),
                                        be_within(0.0001).of(43.958))
  end
end
