# frozen_string_literal: true

require "spec_helper"

module SequenceClosureBranchesSpecHelpers
  def scene_for(body, **)
    diagram = Sirena::Parser::Sequence.new.parse("sequenceDiagram\n#{body}\n")
    Sirena::Layout::Sequence.new.call(diagram, **)
  end

  def gap_after_a(children, edges: [], notes: [])
    Sirena::Layout::Sequence::ActorGaps
      .new(children, edges, notes, font_size: 16).extra_after("A")
  end

  def note_entry(ids, message_index: 0, order: 1)
    { text: "hi", position: "over", message_index: message_index,
      order: order, participant_ids: ids }
  end
end

# Arms the shared-graph path leaves unreached. Where no parsed diagram can
# produce the input (every participant a message names is declared), the
# example drives the internal class or private method directly and says so.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceClosureBranchesSpecHelpers

  describe "theme without a sequence font size" do
    let(:scene) do
      scene_for("participant A", theme: Sirena::Theme.new(name: "bare"))
    end

    it "sets participant text at the default size" do
      expect(scene.participants.first.label.font_size).to eq(16.0)
    end
  end

  describe "a message that creates a participant left of its sender" do
    let(:scene) { scene_for("participant A\ncreate participant B\nZ->>B: hi") }
    let(:shaft) { scene.messages.first.shaft }
    let(:created) { scene.participants.find { |p| p.id == "B" } }

    it "runs right to left" do
      expect(shaft.x1).to be > shaft.x2
    end

    it "stops short of the new box, on its right side" do
      expect(shaft.x2).to be > created.x + created.width
    end
  end

  describe "layout helpers fed shapes a parsed diagram never makes" do
    subject(:layout) { described_class.new }

    it "gives a graph without participants the default canvas width" do
      expect(layout.send(:canvas_width, nil)).to eq(800)
    end

    it "reads the width of an already placed participant" do
      placed = described_class::Participant.new(id: "A", width: 77.0)

      expect(layout.send(:participant_width_value, placed)).to eq(77.0)
    end

    it "reads the id of an already placed participant" do
      placed = described_class::Participant.new(id: "A")

      expect(layout.send(:participant_id, placed)).to eq("A")
    end

    it "finds no endpoints for a message that names none" do
      expect(layout.send(:message_endpoints, {}, { "A" => {} }))
        .to eq([nil, nil])
    end

    it "gives a labelled message without measured labels no size" do
      edge = { metadata: { message_text: "hi" } }
      label = layout.send(:typed_message_label, edge, 0, 100, 50)

      expect([label.text, label.width, label.height])
        .to eq(["hi", nil, nil])
    end

    {
      "right-pointing" => [0, 10, 2.0],
      "left-pointing" => [10, 0, 8.0],
    }.each do |name, (from_x, tip_x, back_x)|
      it "backs a #{name} open head off its tip" do
        lines = layout.send(:open_head, from_x, tip_x, 5)

        expect(lines.map(&:x2)).to eq([back_x, back_x])
      end
    end
  end

  describe Sirena::Layout::Sequence::ActorGaps do
    let(:children) do
      [{ id: "A", width: 100 }, { id: "B", width: 100 }]
    end
    let(:long) { "a rather long message text to claim room" }

    it "ignores a message that names an undeclared participant" do
      edge = { sources: ["A"], targets: ["Z"],
               metadata: { message_source: long } }

      expect(gap_after_a(children, edges: [edge])).to eq(0)
    end

    it "ignores a note that names only undeclared participants" do
      note = { text: long, position: "right_of", participant_ids: ["Z"] }

      expect(gap_after_a(children, notes: [note])).to eq(0)
    end

    it "still widens the gap for a declared neighbour" do
      edge = { sources: ["A"], targets: ["B"],
               metadata: { message_source: long } }

      expect(gap_after_a(children, edges: [edge])).to be > 0
    end
  end

  describe Sirena::Layout::Sequence::MessageRows do
    it "wraps a message to an unplaced participant at one actor box wide" do
      text = "word " * 12
      edge = { sources: ["A"], targets: ["Z"],
               metadata: { message_source: text } }
      rows = described_class.new([edge], { "A" => { center_x: 0 } },
                                 font_size: 16, wrap: true)
      narrow = Sirena::Layout::Sequence::TextWrap.lines(
        text, described_class::MIN_LIMIT, 16
      )

      expect(rows.lines(0)).to eq(narrow)
    end
  end

  describe Sirena::Layout::Sequence::TextWrap do
    it "ends a cut word without a hyphen when its last letter fills the line" do
      expect(described_class.lines("mmmmmmmmmm", 123, 16))
        .to eq(["mmmmmmmmmm"])
    end
  end

  describe Sirena::Layout::Sequence::FramePlacement do
    let(:positions) do
      { "A" => { center_x: 100 }, "B" => { center_x: 300 } }
    end
    let(:frame) do
      { kind: "loop", label: "go", sections: [], start: 0, stop: 1,
        depth: 0, open_order: 1, close_order: 2 }
    end

    it "drops a box none of whose members is placed" do
      box = { title: "", color: nil, members: ["Z"] }
      layout = described_class.new(boxes: [box], ids: %w[A B])

      expect(layout.box_shapes(positions, {}, 200)).to eq([])
    end

    it "spans every participant for a frame whose message names an unplaced one" do
      layout = described_class.new(frames: [frame], spans: [%w[A Z]],
                                   ids: %w[A B])
      shape = layout.frame_shapes(positions, ->(_index) { 100 }).first

      expect([shape.x, shape.x + shape.width]).to eq([89, 311])
    end
  end

  describe Sirena::Layout::Sequence::NotePlacement do
    let(:positions) do
      { "A" => { x: 25, center_x: 100 }, "B" => { center_x: 300 } }
    end

    let(:placement) do
      ->(entries) { described_class.new(entries, positions, font_size: 16) }
    end

    it "leaves out a note that names no placed participant" do
      expect(placement.call([note_entry(["Z"])]).notes).to eq([])
    end

    it "keeps the note that does, beside one that does not" do
      expect(placement.call([note_entry(["Z"]), note_entry(["A"])]).notes.length).to eq(1)
    end

    it "gives a wrapped note over a participant without a box edge the minimum width" do
      rows = Sirena::Layout::Sequence::MessageRows.new(
        [], positions, font_size: 16, wrap: true
      )
      placed = described_class.new([note_entry(["B"])], positions,
                                   font_size: 16, rows: rows)
      note = placed.notes.first

      expect(note.width).to eq(Sirena::Layout::Sequence::NoteBox::MIN_WIDTH)
    end

    it "does not stack a later message's slot above an earlier-listed note" do
      entries = [note_entry(["A"], message_index: 2), note_entry(["A"], message_index: 0)]
      lone = placement.call([note_entry(["A"], message_index: 0)]).notes.first
      second = placement.call(entries).notes.last

      expect(second.y).to eq(lone.y)
    end
  end
end
