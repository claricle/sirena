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

  def simple_source
    <<~MERMAID
      kanban
        todo[Todo]
          docs[Write docs]
          docs[Ship docs]
    MERMAID
  end

  def simple_result
    [recognized(Sirena.render(simple_source)), recognizer.container_kinds]
  end

  def expected_simple_result
    [[[:section, "Todo", nil, :label],
      [:card, "Write docs", "Todo", :label],
      [:card, "Ship docs", "Todo", :label]], [:section]]
  end

  def real_labels
    name = "001_rendering_kanban_spec_kanban_0"
    reference = reference_svg("kanban/#{name}.svg")
    sirena = Sirena.render(corpus_source("kanban/#{name}.mmd"))
    [reference, sirena].map do |svg|
      recognized(svg).map { |item| item.first(2) }
    end
  end

  def expected_real_labels
    [[[:section, "Todo"],
      [:card, "Create Documentation"],
      [:card, "Create Blog about the new diagram"]],
     [[:section, "Todo"],
      [:card, "Create Documentation"],
      [:card, "Create Blog about thenew diagram"]]]
  end

  it "recognizes sections and repeated cards by their shared labels" do
    expect(simple_result).to eq(expected_simple_result)
  end

  it "joins a wrapped card's lines without the break space" do
    expect(real_labels).to eq(expected_real_labels)
  end
end
