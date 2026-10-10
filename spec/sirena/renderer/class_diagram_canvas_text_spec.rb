# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/class_diagram"
require "sirena/renderer/class_diagram"

RSpec.describe Sirena::Renderer::ClassDiagram do
  it "positions namespace titles in the layout" do
    _, boxes = namespace_layout.flatten([namespace_node])

    expect([boxes.first.title_x, boxes.first.title_y]).to eq([70.0, 42.0])
  end

  it "positions note text in the layout" do
    note = note_layout.notes([note_node], {}).first

    expect([note.text_x, note.text_y]).to eq([75.0, 43.0])
  end

  it "renders the final text anchors without deriving coordinates" do
    anchors = rendered_text.map do |text|
      [Array(text.content).join, text.x, text.y]
    end

    expect(anchors).to include(["Domain", 7.0, 11.0], ["Memo", 13.0, 17.0])
  end

  def namespace_layout
    Sirena::Layout::ClassNamespaceNodes.new(
      size: ->(_title) { { width: 40, height: 16 } },
    )
  end

  def namespace_node
    {
      id: "namespace:Domain", x: 10, y: 20, width: 120, height: 80,
      children: [], metadata: { title: "Domain" }
    }
  end

  def note_layout
    Sirena::Layout::ClassNoteNodes.new(
      font_size: 16, measure: ->(_text, _size) { 50 },
      connect: ->(_from, _to) { { x: 0, y: 0 } }
    )
  end

  def note_node
    {
      id: "note:0", x: 15, y: 20, width: 120, height: 40,
      metadata: { note: true, text: "Memo", target_id: nil }
    }
  end

  def rendered_text
    renderer = Sirena::Renderer::ClassDiagram.new(
      theme: Sirena::Theme::Registry.get(:default),
    )
    renderer.render(scene).children.grep(Sirena::Svg::Group)
      .flat_map(&:children).grep(Sirena::Svg::Text)
  end

  def scene
    Sirena::Layout::ClassDiagram::Scene.new(
      width: 100, height: 100, view_box: "0 0 100 100",
      namespaces: [namespace_box], notes: [note]
    )
  end

  def namespace_box
    Sirena::Layout::ClassNamespaceBox.new(
      id: "Domain", title: "Domain", x: 1, y: 2, width: 20, height: 30,
      title_x: 7, title_y: 11
    )
  end

  def note
    Sirena::Layout::ClassNote.new(
      id: "0", text: "Memo", x: 2, y: 3, width: 30, height: 20,
      text_x: 13, text_y: 17
    )
  end
end
