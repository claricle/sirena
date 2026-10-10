# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Pie do
  subject(:renderer) { described_class.new }

  let(:svg) { Sirena::Svg::Document.new }

  def hook(name, *arguments)
    renderer.send(name, *arguments)
  end

  def label_text
    Array(svg.children.grep(Sirena::Svg::Text).first.content).join
  end

  it "adds room for a title above the pie" do
    expect(hook(:calculate_height_for_pie, { title: "T" })).to eq(460)
  end

  it "keeps the compact height for a pie without a title" do
    expect(hook(:calculate_height_for_pie, {})).to eq(400)
  end

  it "flags a slice over half the circle as a large arc" do
    expect(hook(:create_pie_slice_path, 0, 270)).to include("A 150 150 0 1 1")
  end

  it "flags a slice under half the circle as a small arc" do
    expect(hook(:create_pie_slice_path, 0, 90)).to include("A 150 150 0 0 1")
  end

  it "appends the percentage to a label when data is shown" do
    hook(:render_label, "A", 25.0, 1, 2, svg, true)

    expect(label_text).to eq("A: 25.0%")
  end

  it "writes only the name when data is hidden" do
    hook(:render_label, "A", 25.0, 1, 2, svg, false)

    expect(label_text).to eq("A")
  end

  it "draws no slices for a graph without slices" do
    hook(:render_slices, {}, svg)

    expect(svg.children).to be_empty
  end

  it "draws one path per slice" do
    slices = [{ angle: 90.0 }, { angle: 270.0 }]
    hook(:render_slices, { slices: slices }, svg)

    expect(svg.children.grep(Sirena::Svg::Path).length).to eq(2)
  end

  it "writes no labels for a graph without slices" do
    hook(:render_labels, {}, svg)

    expect(svg.children).to be_empty
  end

  it "writes each slice label with its percentage" do
    slices = [{ angle: 90.0, label: "A", percentage: 25.0 }]
    hook(:render_labels, { slices: slices, show_data: true }, svg)

    expect(label_text).to eq("A: 25.0%")
  end
end
