# frozen_string_literal: true

# Helpers for the sequence frame and box specs.
module SequenceFrameHelpers
  def parse_sequence(body)
    Sirena::Parser::Sequence.new.parse("sequenceDiagram\n#{body}\n")
  end

  def render_sequence(body)
    Sirena::Engine.new.render("sequenceDiagram\n#{body}\n")
  end

  def ir_field(graph, parent, role)
    graph.nodes.find { |n| n.parent_id == parent && n.role == role }&.label
  end

  def layout_scene(body)
    Sirena::Layout::Sequence.new.call(parse_sequence(body))
  end

  def mermaid_scene(source)
    parsed = Sirena::Notation::Mermaid.parse(source)
    Sirena::Layout::Sequence.new.call(parsed.diagram)
  end

  def mermaid_last_x(source)
    mermaid_scene(source).participants.last.x
  end

  def note_line_texts(text)
    scene = layout_scene("A->>B: x\nNote right of A: #{text}")
    scene.notes.first.lines.map(&:text)
  end

  def actor_xs(scene)
    scene.participants.map(&:x)
  end

  def last_actor_x(body)
    actor_xs(layout_scene(body)).last
  end

  def box_of(shape)
    [shape.x, shape.y, shape.width, shape.height]
  end

  def bottom_of(shape)
    shape.y + shape.height
  end

  def message_rows(scene)
    scene.messages.map { |message| message.shaft.y1 }
  end

  def frame_summary(frame)
    [frame.kind, frame.label, frame.start_index, frame.end_index,
     frame.depth]
  end
end
