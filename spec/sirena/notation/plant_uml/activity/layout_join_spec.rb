# frozen_string_literal: true

require "spec_helper"
require_relative "activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity::Layout do
  include ActivityHelpers

  def diamond(scene)
    scene.marks.find do |m|
      m.kind == :polygon && m.attrs[:role] == :diamond &&
        m.attrs[:points].size == 4
    end.attrs[:points]
  end

  def rects(scene)
    scene.marks.select { |m| m.kind == :rect }.map(&:attrs)
  end

  def gap_above_join(source)
    scene = layout(source)
    action_bottom = rects(scene).map { |r| r[:y] + r[:height] }.max
    diamond(scene).map(&:last).min - action_bottom
  end

  it "closes two branches at the side of the diamond, 6 below the row" do
    expect(gap_above_join("if (x?) then (y)\n:a;\nelse (n)\n:b;\nendif"))
      .to be_within(0.01).of(6.0)
  end

  it "drops the middle of three branches into the diamond's top, 20 below",
     :aggregate_failures do
    source = ["switch (t?)", "case (a)", ":one;", "case (b)", ":two;",
              "case (c)", ":three;", "endswitch"].join("\n")

    expect(gap_above_join(source)).to be_within(0.01).of(20.0)
  end

  it "runs a fork's closing bar round to the side of the diamond" do
    scene = layout(["if (m?) then (y)", "fork", ":a;", "fork again", ":b;",
                    "end fork", "else (n)", ":c;", ":d;", "endif"].join("\n"))

    expect(path_ends(scene)).to include(left_tip(diamond(scene)))
  end

  def path_ends(scene)
    scene.marks.select { |m| m.kind == :path }.map { |m| m.attrs[:points].last }
  end

  def left_tip(points)
    [points.map(&:first).min, points.sum(&:last) / 4.0]
  end

  context "with a decision whose else branch is in another swimlane" do
    let(:scene) do
      layout(["|#pink|One|", "start", "if (c?) then (y)", ":a;", "else (n)",
              "|Two|",
              ":b;", "endif", "stop"].join("\n"))
    end

    it "keeps the closing diamond in the decision's swimlane" do
      band = rects(scene).first
      centre = diamond(scene).map(&:first).uniq.first

      expect(centre).to be_between(band[:x], band[:x] + band[:width])
    end

    it "starts the next swimlane where the first ends" do
      first, second = rects(scene).first(2)

      expect(second[:x]).to be >= first[:x] + first[:width]
    end
  end
end
