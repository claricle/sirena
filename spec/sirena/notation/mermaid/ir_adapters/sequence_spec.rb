# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/sequence"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Sequence do
  let(:diagram) { representative_diagram }
  let(:ir) { described_class.call(diagram) }

  it "produces valid collision-safe graph IR with root metadata" do
    expect(root_signature).to eq(expected_root_signature)
  end

  it "preserves participant declaration order, aliases, and types" do
    expect(participant_signature).to eq(expected_participant_signature)
  end

  it "preserves message order, endpoints, labels, and arrow semantics" do
    expect(message_signature).to eq(expected_message_signature)
  end

  it "preserves note timing, placement, and ordered participant references" do
    expect(note_signature).to eq(expected_note_signature)
  end

  it "preserves activation timing and participant identity" do
    expect(activation_signature).to eq(expected_activation_signature)
  end

  def representative_diagram
    diagram = Sirena::Diagram::Sequence.new(
      id: "message_0", title: "Checkout", direction: "TB", theme: "dark",
      participants: participants, messages: messages,
      notes: notes, activations: activations
    )
    add_optional_metadata(diagram)
  end

  def participants
    [
      participant("message_0", "Alice", "actor"),
      participant("message_0_details", "Bob", "participant"),
      participant("note_0", "Carol", "participant"),
      participant("activation_0", "Dan", "participant"),
      participant("diagram_settings", "Eve", "participant"),
    ]
  end

  def participant(id, label, actor_type)
    Sirena::Diagram::SequenceParticipant.new(
      id: id, label: label, actor_type: actor_type,
    )
  end

  def messages
    [
      message("message_0", "message_0_details", "wrap: hello<br>again",
              %w[dotted open both]),
      message("note_0", "activation_0", "done", %w[solid cross target]),
    ]
  end

  def message(from, to, text, style)
    line, head, side = style
    Sirena::Diagram::SequenceMessage.new(
      from_id: from, to_id: to, message_text: text,
      line_style: line, head_style: head, head_side: side
    )
  end

  def notes
    [Sirena::Diagram::SequenceNote.new(
      text: "In flight", position: "over",
      participant_ids: %w[message_0 message_0_details], message_index: 1
    )]
  end

  def activations
    [Sirena::Diagram::SequenceActivation.new(
      participant_id: "diagram_settings", start_index: 0, end_index: 2,
    )]
  end

  def add_optional_metadata(diagram)
    diagram.define_singleton_method(:acc_title) { "Accessible checkout" }
    diagram.define_singleton_method(:acc_description) do
      "Checkout interactions"
    end
    diagram.define_singleton_method(:autonumber) { "10 2" }
    diagram
  end

  def root_signature
    settings = ir.nodes.find { |node| node.role == "diagram_settings" }
    [ir.valid?, ir.id, collision_free?, *root_metadata_signature,
     child_signature(settings.id)]
  end

  def root_metadata_signature
    [ir.label, ir.accessibility_title, ir.accessibility_description]
  end

  def expected_root_signature
    [
      true, "message_0_3", true, "Checkout", "Accessible checkout",
      "Checkout interactions",
      [["diagram_identifier", "message_0"], ["layout_direction", "TB"],
       ["theme_reference", "dark"], ["autonumber", "10 2"]]
    ]
  end

  def collision_free?
    ids = [ir.id, *ir.nodes.map(&:id), *ir.edges.map(&:id)]
    ids.uniq.length == ids.length
  end

  def participant_signature
    ir.nodes.filter_map do |node|
      next unless participant_role?(node.role)

      [node.id, node.label, node.role, child_signature(node.id)]
    end
  end

  def expected_participant_signature
    ids = %w[message_0 message_0_details note_0 activation_0
             diagram_settings]
    labels = %w[Alice Bob Carol Dan Eve]
    ids.each_with_index.map do |id, index|
      type = index.zero? ? "actor" : "participant"
      [id, labels[index], type,
       [["original_identifier", id], ["participant_type", type],
        ["sequence_index", index.to_s]]]
    end
  end

  def participant_role?(role)
    case role
    when "participant", "actor" then true
    else false
    end
  end

  def message_signature
    ir.edges.select { |edge| edge.role == "message" }.map do |edge|
      [edge.id, edge.source_id, edge.target_id, edge.label,
       child_signature(edge.parent_id)]
    end
  end

  def expected_message_signature
    [
      ["message_0_2", "message_0", "message_0_details",
       "wrap: hello<br>again",
       [["line_style", "dotted"], ["head_style", "open"],
        ["head_side", "both"], ["sequence_index", "0"]]],
      ["message_1", "note_0", "activation_0", "done",
       [["line_style", "solid"], ["head_style", "cross"],
        ["head_side", "target"], ["sequence_index", "1"]]],
    ]
  end

  def note_signature
    note = ir.nodes.find { |node| node.role == "note" }
    targets = ir.edges.select { |edge| edge.role == "note_reference" }
      .map(&:target_id)
    [note.id, note.label, child_signature(note.id), targets]
  end

  def expected_note_signature
    ["note_0_2", "In flight",
     [["note_position", "over"], ["message_index", "1"]],
     %w[message_0 message_0_details]]
  end

  def activation_signature
    activation = ir.nodes.find { |node| node.role == "activation" }
    reference = ir.edges.find { |edge| edge.role == "activation_reference" }
    [activation.id, child_signature(activation.id), reference.target_id]
  end

  def expected_activation_signature
    ["activation_0_2", [["start_index", "0"], ["end_index", "2"]],
     "diagram_settings"]
  end

  def child_signature(parent_id)
    ir.nodes.select { |node| node.parent_id == parent_id }
      .map { |node| [node.role, node.label] }
  end
end
