# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::KanbanRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.identity]
    end
  end

  it "recognizes sections and repeated cards by their shared labels" do
    source = <<~MERMAID
      kanban
        todo[Todo]
          docs[Write docs]
          docs[Ship docs]
    MERMAID
    sirena = Sirena.render(source)

    expect(recognized(sirena)).to eq(
      [
        [:section, "Todo", nil, :label],
        [:card, "Write docs", "Todo", :label],
        [:card, "Ship docs", "Todo", :label],
      ],
    )
    expect(recognizer.container_kinds).to eq([:section])
  end

  it "keeps a real reference's full label so truncation remains visible" do
    name = "001_rendering_kanban_spec_kanban_0"
    reference = reference_svg("kanban/#{name}.svg")
    sirena = Sirena.render(corpus_source("kanban/#{name}.mmd"))

    expect(recognized(reference).map { |item| item.first(2) }).to eq(
      [
        [:section, "Todo"],
        [:card, "Create Documentation"],
        [:card, "Create Blog about the new diagram"],
      ],
    )
    expect(recognized(sirena).map { |item| item.first(2) }).to eq(
      [
        [:section, "Todo"],
        [:card, "Create Documentation"],
        [:card, "Create Blog about the ..."],
      ],
    )
  end
end
