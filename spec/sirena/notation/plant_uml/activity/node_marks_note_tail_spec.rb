# frozen_string_literal: true

require "spec_helper"
require_relative "activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity::NodeMarks do
  include ActivityHelpers

  let(:scene) { layout(":a;\nnote #{side}: hello") }
  let(:points) do
    scene.marks.find { |m| m.kind == :polygon && m.attrs[:fill] == "#FEFFDD" }
      .attrs[:points]
  end
  let(:node) do
    index = scene.marks.index { |m| m.attrs[:content] == "a" }
    scene.marks[0...index].reverse.find { |m| m.kind == :rect }.attrs
  end
  let(:mid) { points.map(&:last).minmax.sum / 2.0 }

  it "draws no dashed connector" do
    expect(layout(":a;\nnote right: hello").marks.filter_map do |m|
      m.attrs[:dash]
    end).to be_empty
  end

  context "with a right-hand note" do
    let(:side) { "right" }

    it "wedges from the note's left edge to the node's right border",
       :aggregate_failures do
      tip = points.min_by(&:first)

      expect(tip).to eq([node[:x] + node[:width], mid])
      expect(points.count { |p| p.first == points.map(&:first).minmax[0] })
        .to eq(1)
    end
  end

  context "with a left-hand note" do
    let(:side) { "left" }

    it "wedges from the note's right edge to the node's left border" do
      expect(points.max_by(&:first)).to eq([node[:x], mid])
    end
  end
end
