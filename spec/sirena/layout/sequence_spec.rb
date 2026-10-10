# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/sequence"

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

  describe "typed final-canvas geometry" do
    subject(:scene_evidence) do
      participant = scene.participants.first
      lifeline = scene.lifelines.first
      message = scene.messages.first
      [
        scene.class, scene.width, scene.height, scene.view_box,
        [participant.id, participant.x, participant.y,
         participant.width, participant.height],
        [lifeline.x1, lifeline.y1, lifeline.x2, lifeline.y2],
        [message.shaft.x1, message.shaft.y1,
         message.shaft.x2, message.shaft.y2],
        message.heads.first.points,
        [message.label.text, message.label.x, message.label.y]
      ]
    end

    let(:expected_scene_evidence) do
      [
        described_class::Scene, 450.0, 215.0, "0 0 450 215",
        ["A", 50.0, 10.0, 150.0, 65.0],
        [125.0, 75.0, 125.0, 139.0],
        [125.0, 119.0, 317.0, 119.0],
        "325,119 317,115 317,123",
        ["hello", 225.0, 109.0]
      ]
    end

    it "returns typed final-canvas geometry" do
      expect(scene_evidence).to eq(expected_scene_evidence)
    end
  end

  it "does not send its hand-laid-out Scene through Grid" do
    calls = []
    allow(Sirena::Layout::Grid).to receive(:apply) { calls << :apply }

    result = described_class.new.call(diagram)

    expect([result.class, calls]).to eq([described_class::Scene, []])
  end

  describe "themed label geometry" do
    subject(:theme_evidence) do
      themed = described_class.new.call(
        diagram, theme: Sirena::Theme::Registry.get(:high_contrast)
      )
      participant = themed.participants.first.label
      message = themed.messages.first.label
      [participant.font_size, participant.width,
       message.font_size, message.width]
    end

    let(:expected_theme_evidence) do
      [
        18.0,
        Sirena::TextMeasurement.measure("A", font_size: 18.0)[:width],
        18.0,
        Sirena::TextMeasurement.measure("hello", font_size: 18.0)[:width],
      ]
    end

    it "uses the injected sizes for measurement and final labels" do
      expect(theme_evidence).to eq(expected_theme_evidence)
    end
  end

  describe "participant with an odd width" do
    let(:diagram) do
      Sirena::Parser::Sequence.new.parse(
        "sequenceDiagram\nparticipant WWWWWWWWWWi\nparticipant B\n",
      )
    end

    it "centres its label on the half pixel" do
      expect(described_class.new.call(diagram).participants.first.label.x)
        .to eq(137.5)
    end
  end

  describe "note with an odd width" do
    let(:diagram) do
      Sirena::Parser::Sequence.new.parse(
        "sequenceDiagram\nparticipant A\nparticipant B\nA->>B: x\n" \
        "Note right of A: WWWWWWWWWWi\n",
      )
    end

    it "centres its text on the half pixel" do
      expect(described_class.new.call(diagram).notes.first.lines.first.x)
        .to eq(237.5)
    end
  end

  describe "default text size" do
    it "sets participant and message text at mmdc's 16px" do
      labels = [scene.participants.first.label, scene.messages.first.label]

      expect(labels.map(&:font_size)).to eq([16.0, 16.0])
    end
  end

  describe "wide themed label geometry" do
    subject(:geometry_checks) do
      first, second = contrast_scene.participants
      label_left = first.label.x - (first.label.width / 2)
      label_right = first.label.x + (first.label.width / 2)
      {
        measured_width: first.width == described_class::TextWidth.of(
          "WWWWWWWWW", 18
        ) + described_class::PARTICIPANT_LABEL_PADDING,
        next_position: second.x == first.x + first.width +
          described_class::PARTICIPANT_MARGIN,
        label_center: first.label.x == first.x + (first.width / 2),
        lifeline_center: contrast_scene.lifelines.first.x1 == first.label.x,
        message_source: contrast_scene.messages.first.shaft.x1 == first.label.x,
        message_target: contrast_scene.messages.first.shaft.x2 ==
          second.label.x - described_class::ARROW_SIZE,
        left_containment: label_left >= first.x,
        right_containment: label_right <= first.x + first.width,
        box_expansion: scene.participants.first.width < first.width,
        canvas_expansion: scene.width < contrast_scene.width,
      }
    end

    let(:source) do
      "sequenceDiagram\nparticipant WWWWWWWWW\nparticipant B\n" \
        "WWWWWWWWW->>B: hello\n"
    end
    let(:contrast_scene) do
      described_class.new.call(
        diagram, theme: Sirena::Theme::Registry.get(:high_contrast)
      )
    end

    it "expands participants and all dependent geometry" do
      expect(geometry_checks.values).to all(be(true))
    end
  end

  describe "activations stay undrawn while notes get a slot" do
    subject(:omission_evidence) do
      decorated = Sirena::Parser::Sequence.new.parse(
        "sequenceDiagram\nparticipant A\nparticipant B\n" \
        "Note over A: omitted\nactivate A\nA->>B: hello\ndeactivate A\n",
      )
      result = described_class.new.to_graph(decorated)
      [result.height, result.messages.length, result.lifelines.map(&:y2),
       result.notes.length, result.respond_to?(:activations)]
    end

    it "adds a note slot but no activation geometry" do
      expect(omission_evidence).to eq([264.0, 1, [188.0, 188.0], 1, false])
    end
  end

  describe "shared graph IR" do
    it "lays out aliases, fragments, notes, and activations identically" do
      diagram = Sirena::Parser::Sequence.new.parse(representative_source)
      actual, expected = scene_round_trip(diagram)

      expect(actual).to eq(expected)
    end

    it "retains alias, actor, message, and self-loop rendering through IR" do
      diagram = Sirena::Parser::Sequence.new.parse(representative_source)
      graph = Sirena::Notation::Mermaid::IRAdapters::Sequence.call(diagram)
      result = described_class.new.call(graph)

      expect(shared_scene_signature(result)).to eq(expected_shared_signature)
    end
  end

  def representative_source
    <<~MERMAID
      sequenceDiagram
        actor A as Alice
        box Services
          participant B as Bob
          A->>+B: wrap: request<br>accepted
          Note over A,B: in flight
          B-->>-A: response
        end
        loop Retry
          A-)A: retry
        end
    MERMAID
  end

  def scene_round_trip(diagram)
    before = Marshal.dump(diagram)
    graph = Sirena::Notation::Mermaid::IRAdapters::Sequence.call(diagram)
    private_scene = described_class.new.call(diagram)
    shared_scene = described_class.new.call(graph)
    actual = [Marshal.dump(shared_scene), Marshal.dump(diagram)]
    [actual, [Marshal.dump(private_scene), before]]
  end

  def shared_scene_signature(result)
    participants = result.participants.map do |participant|
      [participant.id, participant.actor_type, participant.label.text]
    end
    messages = result.messages.map do |message|
      [message.line_style, message.label&.text, !message.loop_path.nil?]
    end
    [participants, messages]
  end

  def expected_shared_signature
    [
      [%w[A actor Alice], %w[B participant Bob]],
      [["solid", "request accepted", false],
       ["dotted", "response", false], ["solid", "retry", true]],
    ]
  end
end
