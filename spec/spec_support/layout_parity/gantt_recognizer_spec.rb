# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::GanttRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.identity]
    end
  end

  def real_pair
    name = "017_parser_should_handle_a_task_definition_16"
    reference = reference_svg("gantt/#{name}.svg")
    sirena = Sirena.render(corpus_source("gantt/#{name}.mmd"))
    [recognized(reference), recognized(sirena)]
  end

  def pair_summary
    real_pair.map do |elements|
      [elements.select { |item| item.first == :task },
       elements.count { |item| item.first == :tick }]
    end
  end

  def tick_extremes
    reference, sirena = real_pair.map do |side|
      side.select { |item| item.first == :tick }
    end
    [reference.first, reference.last, sirena.first, sirena.last]
  end

  def expected_tick_extremes
    first = [:tick, "2014-01-01", :label]
    last = [:tick, "2014-01-04", :label]
    [first, last, first, last]
  end

  it "keys the real task by its row label on both sides" do
    task = [[:task, "Design jison grammar", :label]]

    expect(pair_summary).to eq([[task, 13], [task, 13]])
  end

  it "reads the same first and last date tick on both sides" do
    expect(tick_extremes).to eq(expected_tick_extremes)
  end
end
