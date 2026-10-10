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
      [:card, "Create Blog about the new diagram"]]]
  end

  let(:metadata_card_labels) do
    %w[
      007_rendering_kanban_spec_kanban_6
      009_rendering_kanban_spec_kanban_8
      010_rendering_kanban_spec_kanban_9
    ].map do |name|
      reference = reference_svg("kanban/#{name}.svg")
      sirena = Sirena.render(corpus_source("kanban/#{name}.mmd"))
      [reference, sirena].map do |svg|
        recognized(svg).select { |item| item.first == :card }
      end
    end
  end

  it "recognizes sections and repeated cards by their shared labels" do
    expect(simple_result).to eq(expected_simple_result)
  end

  it "separates a wrapped card's lines with spaces" do
    expect(real_labels).to eq(expected_real_labels)
  end

  it "uses the primary card label instead of metadata values" do
    expect(metadata_card_labels)
      .to all(satisfy { |reference, sirena| reference == sirena })
  end
end
