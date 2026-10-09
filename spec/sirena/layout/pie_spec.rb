# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/pie"

RSpec.describe Sirena::Layout::Pie do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Pie.new }

  it "keeps an empty pie renderable" do
    expect(graph).to include(empty_graph)
  end

  it "transforms populated slices and their proportions" do
    populate_diagram
    expect(graph).to eq(populated_graph)
  end

  def empty_graph
    {
      id: "pie",
      show_data: false,
      slices: [],
      metadata: { total_value: 0, slice_count: 0 },
    }
  end

  def populate_diagram
    diagram.slices = [slice("Small", 1), slice("Large", 3)]
    diagram.id = "share"
    diagram.title = "Market share"
    diagram.show_data = true
    populate_accessibility
  end

  def populate_accessibility
    diagram.acc_title = "Share by product"
    diagram.acc_description = "One quarter and three quarters"
  end

  def populated_graph
    {
      id: "share",
      title: "Market share",
      show_data: true,
      acc_title: "Share by product",
      acc_description: "One quarter and three quarters",
      slices: expected_slices,
      metadata: { total_value: 4.0, slice_count: 2 },
    }
  end

  def slice(label, value)
    Sirena::Diagram::PieSlice.new(label: label, value: value)
  end

  def expected_slices
    [small_slice, large_slice]
  end

  def small_slice
    {
      id: "slice_0", label: "Small", value: 1.0,
      percentage: 25.0, angle: 90.0, index: 0
    }
  end

  def large_slice
    {
      id: "slice_1", label: "Large", value: 3.0,
      percentage: 75.0, angle: 270.0, index: 1
    }
  end
end
