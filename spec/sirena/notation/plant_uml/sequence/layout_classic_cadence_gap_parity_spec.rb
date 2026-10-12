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

  def arrow_ys(scene)
    scene.arrows.map { |arrow| arrow.path[/M \S+ (\S+)/, 1].to_f }
  end

  it "sizes classic heads to the PlantUML label advance plus fourteen" do
    heads = scene_of("participant A", "participant B", "A -> B")
      .heads.first(2)

    expect(heads.map(&:width)).to contain_exactly(
      be_within(0.0001).of(23.6592),
      be_within(0.0001).of(22.0527),
    )
  end

  it "leaves PlantUML's ten-pixel floor between unforced classic heads" do
    heads = scene_of("participant A", "participant B", "A -> B")
      .heads.first(2)

    expect(heads.last.x - (heads.first.x + heads.first.width)).to eq(10.0)
  end

  it "uses PlantUML's classic first-row and message cadence" do
    scene = scene_of("participant A", "participant B",
                     "A -> B: hello", "B -> A: back")

    expect(arrow_ys(scene)).to eq([82.7988, 112.1093])
  end

  it "uses PlantUML's classic fragment-header cadence" do
    scene = scene_of("participant A", "participant B", "group Setup",
                     "A -> B: hello", "end", "B -> A: back")

    expect(arrow_ys(scene)).to eq([107.1093, 146.4198])
  end

  it "keeps divider and deactivation clearance on PlantUML's cadence" do
    scene = scene_of('participant "App" as App', 'actor "OEM" as OEM',
                     "== Process A ==", "App -> OEM: Inform OEM",
                     "activate OEM", "deactivate OEM", "== Process B ==",
                     "App -> OEM: Inform OEM again", "activate OEM",
                     "deactivate OEM")

    expect(arrow_ys(scene)).to eq([171.1093, 273.7303])
  end

  it "ends a classic message before the activation bar" do
    scene = scene_of('participant "App" as App', 'actor "OEM" as OEM',
                     "App -> OEM: Inform OEM", "activate OEM")
    endpoint = scene.arrows.first.path[/L (\S+) /, 1].to_f

    expect(scene.lifelines.last.x1 - endpoint).to eq(7.0)
  end

  it "does not separate peers to make room for a one-participant note" do
    scene = scene_of("Bob -> Alice: hello", "alt link",
                     "note over Bob: [[https://www.google.com]]", "end")
    heads = scene.heads.first(2)

    expect(heads.last.x - (heads.first.x + heads.first.width))
      .to be_within(0.0001).of(11.7178)
  end
end
