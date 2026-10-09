# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence do
  let(:source) do
    <<~MERMAID
      sequenceDiagram
          participant A
          participant B
          A->>B: hello
    MERMAID
  end
  let(:diagram) { Sirena::Parser::Sequence.new.parse(source) }
  let(:scene) { described_class.new.to_graph(diagram) }

  it "returns typed final-canvas geometry" do
    participant = scene.participants.first
    lifeline = scene.lifelines.first
    message = scene.messages.first
    evidence = [
      scene.class, scene.width, scene.height, scene.view_box,
      [participant.id, participant.x, participant.y,
       participant.width, participant.height],
      [lifeline.x1, lifeline.y1, lifeline.x2, lifeline.y2],
      [message.shaft.x1, message.shaft.y1,
       message.shaft.x2, message.shaft.y2],
      message.heads.first.points,
      [message.label.text, message.label.x, message.label.y]
    ]

    expect(evidence).to eq([
                             described_class::Scene, 400.0, 280.0, "0 0 400 280",
                             ["A", 20.0, 20.0, 120.0, 40.0],
                             [80.0, 60.0, 80.0, 220.0],
                             [80.0, 120.0, 212.0, 120.0],
                             "220,120 212,116 212,124",
                             ["hello", 150.0, 110.0]
                           ])
  end

  it "does not send its hand-laid-out Scene through Grid" do
    calls = []
    allow(Sirena::Layout::Grid).to receive(:apply) { calls << :apply }

    result = described_class.new.call(diagram)

    expect([result.class, calls]).to eq([described_class::Scene, []])
  end

  it "uses the injected theme sizes for measurement and final labels" do
    layout = described_class.new
    layout.theme = Sirena::Theme::Registry.get(:high_contrast)
    themed = layout.to_graph(diagram)
    participant = themed.participants.first.label
    message = themed.messages.first.label

    expect([
             participant.font_size, participant.width,
             message.font_size, message.width
           ]).to eq([
                      16.0, Sirena::TextMeasurement.measure("A", font_size: 16.0)[:width],
                      14.0, Sirena::TextMeasurement.measure("hello", font_size: 14.0)[:width]
                    ])
  end

  it "expands participants and all dependent geometry around themed labels" do
    wide = Sirena::Parser::Sequence.new.parse(
      "sequenceDiagram\nparticipant WWWWWWWWW\nparticipant B\n" \
      "WWWWWWWWW->>B: hello\n",
    )
    default_scene = described_class.new.call(wide)
    contrast_scene = described_class.new.call(
      wide, theme: Sirena::Theme::Registry.get(:high_contrast)
    )
    first, second = contrast_scene.participants
    label_left = first.label.x - (first.label.width / 2)
    label_right = first.label.x + (first.label.width / 2)
    expected = [
      first.label.width + described_class::PARTICIPANT_LABEL_PADDING,
      first.x + first.width + described_class::PARTICIPANT_MARGIN,
      first.x + (first.width / 2), first.label.x, first.label.x,
      second.label.x - described_class::ARROW_SIZE, true, true
    ]
    actual = [
      first.width, second.x, first.label.x,
      contrast_scene.lifelines.first.x1,
      contrast_scene.messages.first.shaft.x1,
      contrast_scene.messages.first.shaft.x2,
      label_left >= first.x, label_right <= first.x + first.width
    ]

    expect([
             actual,
             default_scene.participants.first.width < first.width,
             default_scene.width < contrast_scene.width,
           ]).to eq([expected, true, true])
  end

  it "does not add geometry for notes or activations" do
    decorated = Sirena::Parser::Sequence.new.parse(
      "sequenceDiagram\nparticipant A\nparticipant B\n" \
      "Note over A: omitted\nactivate A\nA->>B: hello\ndeactivate A\n",
    )
    result = described_class.new.to_graph(decorated)

    expect([
             result.height, result.messages.length,
             result.lifelines.map(&:y2), result.respond_to?(:notes),
             result.respond_to?(:activations)
           ]).to eq([280.0, 1, [220.0, 220.0], false, false])
  end
end
