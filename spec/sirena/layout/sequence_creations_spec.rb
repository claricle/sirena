# frozen_string_literal: true

require "spec_helper"

# Expected offsets are read off the pinned mmdc reference of
# sequencediagram_spec-690f7aca: a created participant's box is centred on
# its creating message, its lifeline starts at the box, it sits half a box
# further out than a declared one, and the rows below drop half a box.
RSpec.describe Sirena::Layout::Sequence, :aggregate_failures do
  let(:created_source) do
    <<~MERMAID
      sequenceDiagram
          participant Alice
          participant Bob
          Alice->>Bob: Hello
          create participant Carl
          Alice->>Carl: Hi Carl!
          create actor D as Donald
          Carl->>D: Hi!
          Alice->>Bob: Later
    MERMAID
  end
  let(:declared_source) { created_source.gsub(/^\s*create /, "    ") }
  let(:scene) { scene_for(created_source) }
  let(:half_box) { 65 / 2.0 }

  def scene_for(source)
    diagram = Sirena::Parser::Sequence.new.parse(source)
    described_class.new.to_graph(diagram)
  end

  def participant(scene, id)
    scene.participants.find { |item| item.id == id }
  end

  it "centres a created box on its creating message's line" do
    expect(participant(scene, "Carl").y)
      .to eq(scene.messages[1].shaft.y1 - half_box)
    expect(participant(scene, "D").y)
      .to eq(scene.messages[2].shaft.y1 - half_box)
  end

  it "leaves declared participants on the first row" do
    expect(participant(scene, "Alice").y).to eq(10)
    expect(participant(scene_for(declared_source), "Carl").y).to eq(10)
  end

  it "starts a created lifeline at its box" do
    carl = participant(scene, "Carl")
    lifeline = scene.lifelines.find { |item| item.x1 == carl.x + 75 }

    expect(lifeline.y1).to eq(carl.y + 65)
    expect(scene.lifelines.first.y1).to eq(75)
  end

  it "seats a created participant half a box further out" do
    spread = lambda do |from_scene|
      %w[Bob Carl D].each_cons(2).map do |left, right|
        participant(from_scene, right).x - participant(from_scene, left).x
      end
    end

    expect(spread.call(scene_for(declared_source))).to eq([200, 200])
    expect(spread.call(scene)).to eq([275, 275])
  end

  it "drops the rows below a creating message by half a box" do
    declared = scene_for(declared_source).messages
    ys = ->(messages) { messages.map { |message| message.shaft.y1 } }

    expect(ys.call(scene.messages).each_cons(2).map { |a, b| b - a })
      .to eq([44, 44 + half_box, 44 + half_box])
    expect(ys.call(declared).each_cons(2).map { |a, b| b - a })
      .to eq([44, 44, 44])
  end

  it "stops the creating arrow at the box edge, not the lifeline" do
    carl = participant(scene, "Carl")

    declared = scene_for(declared_source)

    expect(scene.messages[1].shaft.x2).to be <= carl.x
    expect(declared.messages[1].shaft.x2)
      .to be > participant(declared, "Carl").x
  end
end
