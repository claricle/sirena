# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"
  include DejaVuText

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  let(:root) { File.expand_path("../../../../plantuml", __dir__) }
  let(:boundary_source) do
    prefix = "resources.vega.nonreg.group2791."
    suffix = ["note_left_on_self_message",
              "clears_previous_participant--459b540cd94b"].join("_")
    id = "#{prefix}#{suffix}"
    File.read(File.join(root, "sequence", "#{id}.puml"))
  end
  let(:same_box_source) do
    <<~PLANTUML
      @startuml
      box
        participant a
        participant b
      endbox
      a -> b
      @enduml
    PLANTUML
  end

  def scene_of(source)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    parsed.transform.new.call(parsed.diagram)
  end

  it "leaves the JAR gap across a box boundary (self minimum plus overhang)" do
    heads = scene_of(boundary_source).heads.first(2)

    gap = heads.last.x - heads.first.x - heads.first.width

    expect(gap).to be_within(1e-9).of(jar_gap)
  end

  def jar_gap
    first = dejavu("b", size: 14) + 14.0
    second = dejavu("a", size: 14) + 14.0
    title = dejavu("Box A", size: 13, bold: true) + 6.0
    50.0 + ((title - second - 8.0) / 2) - ((first + second) / 2)
  end

  it "retains the ordinary gap between members of the same box" do
    heads = scene_of(same_box_source).heads.first(2)

    expect(heads.last.x - heads.first.x - heads.first.width).to eq(10.0)
  end
end
