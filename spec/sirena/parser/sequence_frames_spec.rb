# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Sequence do
  include SequenceFrameHelpers

  it "records a loop over the message it wraps" do
    diagram = parse_sequence("A->>B: x\nloop Every minute\nA->>B: hi\nend\nA->>B: y")

    expect(diagram.frames.map { |f| frame_summary(f) })
      .to eq([["loop", "Every minute", 1, 2, 0]])
  end

  it "records nested frames with their depth, outer first" do
    diagram = parse_sequence("opt a\nloop b\nA->>B: hi\nend\nend")

    expect(diagram.frames.map { |f| frame_summary(f) })
      .to eq([["opt", "a", 0, 1, 0], ["loop", "b", 0, 1, 1]])
  end

  it "records else dividers at the message that follows them" do
    diagram = parse_sequence("alt ok\nA->>B: x\nelse bad\nA->>B: y\nend")
    sections = diagram.frames.first.sections

    expect(sections.map { |s| [s.kind, s.label, s.start_index] })
      .to eq([["else", "bad", 1]])
  end

  it "records and and option dividers" do
    diagram = parse_sequence("par p\nA->>B: x\nand q\nA->>B: y\nend\n" \
                    "critical c\nA->>B: z\noption o\nA->>B: w\nend")

    expect(diagram.frames.map { |f| f.sections.map(&:kind) })
      .to eq([["and"], ["option"]])
  end

  it "splits a box colour name from its title and lists its members" do
    diagram = parse_sequence("box Aqua Group1\nparticipant A\nparticipant B\nend")
    box = diagram.boxes.first

    expect([box.color, box.title, box.participant_ids])
      .to eq(["Aqua", "Group1", %w[A B]])
  end

  it "keeps an rgb() colour whole" do
    diagram = parse_sequence("box rgb(34, 56, 0) Group1\nparticipant A\nend")

    expect(diagram.boxes.first.color).to eq("rgb(34, 56, 0)")
  end

  it "treats a non-colour first word as part of the title" do
    diagram = parse_sequence("box Team Alpha\nparticipant A\nend")
    box = diagram.boxes.first

    expect([box.color, box.title]).to eq([nil, "Team Alpha"])
  end
end
