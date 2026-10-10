# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Pie, "#call" do
  subject(:scene) { described_class.new.call(diagram) }

  let(:values) { { "Big" => 995, "Tiny" => 5, "Mid" => 50 } }
  let(:diagram) do
    slices = values.map do |label, value|
      Sirena::Diagram::PieSlice.new(label: label, value: value)
    end
    Sirena::Diagram::Pie.new(slices: slices, title: "T")
  end

  def sweep(slice)
    slice.angle.round(6)
  end

  it "draws slice labels at 17px" do
    expect(scene.slices.map { |slice| slice.label.font_size }.uniq)
      .to eq([17.0])
  end

  it "draws the title at 25px" do
    expect(scene.title.font_size).to eq(25.0)
  end

  it "draws legend rows at 17px" do
    expect(scene.legend.map(&:font_size).uniq).to eq([17.0])
  end

  it "draws no slice under one percent of the total" do
    expect(scene.slices.map(&:id)).to eq(%w[slice_0 slice_2])
  end

  it "keeps the legend row of a slice it does not draw" do
    expect(scene.legend.map(&:text)).to eq(%w[Big Tiny Mid])
  end

  it "shares the whole circle among the slices it draws" do
    expect(scene.slices.sum(&:angle)).to be_within(1e-9).of(360.0)
  end

  it "labels a drawn slice with its share of the full total" do
    expect(scene.slices.map { |slice| slice.label.text }).to eq(%w[95% 5%])
  end

  it "keeps colours ranked over every slice, drawn or not" do
    expect(scene.legend.map(&:color_index)).to eq([0, 2, 1])
  end

  it "draws a slice of exactly one percent" do
    values.replace("Big" => 99, "One" => 1)

    expect(scene.slices.length).to eq(2)
  end
end
