# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/sequence"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Sequence do
  include SequenceFrameHelpers

  let(:source) do
    "box Aqua Group1\nparticipant A\nparticipant B\nend\n" \
      "alt ok\nA->>B: x\nelse bad\nA->>B: y\nend"
  end
  let(:ir) { described_class.call(parse_sequence(source)) }

  it "carries a frame with its kind, label and message range" do
    frame = ir.nodes.find { |n| n.role == "frame" }

    expect([frame.label, ir_field(ir, frame.id, "frame_kind"),
            ir_field(ir, frame.id, "start_index"), ir_field(ir, frame.id, "end_index")])
      .to eq(["ok", "alt", "0", "2"])
  end

  it "carries each divider with its label and first message" do
    divider = ir.nodes.find { |n| n.role == "frame_section" }

    expect([divider.label, ir_field(ir, divider.id, "section_kind"),
            ir_field(ir, divider.id, "start_index")]).to eq(["bad", "else", "1"])
  end

  it "carries a box with its colour and title" do
    box = ir.nodes.find { |n| n.role == "box" }

    expect([box.label, ir_field(ir, box.id, "box_color")]).to eq(%w[Group1 Aqua])
  end

  it "links a box to the participants declared inside it" do
    members = ir.edges.select { |e| e.role == "box_member" }

    expect(members.map(&:target_id)).to eq(%w[A B])
  end
end
