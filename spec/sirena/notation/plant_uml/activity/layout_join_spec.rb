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

  it "sets the diamond 23.13 below a closing bar, as PlantUML does" do
    scene = layout(["if (m?) then (y)", "fork", ":a;", "fork again", ":b;",
                    "end fork", "else (n)", ":c;", ":d;", "endif"].join("\n"))
    bar = rects(scene).select { |r| r[:height].round == 6 }.max_by { |r| r[:y] }

    expect(diamond(scene).map(&:last).min - (bar[:y] + bar[:height]))
      .to be_within(0.01).of(23.1328)
  end

  context "with a fork in one branch and two steps in the other" do
    let(:source) do
      ["if (m?) then (y)", "fork", ":a;", "fork again", ":b;", "end fork",
       "else (n)", ":c;", ":d;", "endif"].join("\n")
    end
    let(:scene) { layout(source) }
    let(:steps) do
      scene.marks.select { |m| m.kind == :rect && m.attrs[:height] > 30 }
        .map(&:attrs)
    end
    let(:bars) do
      scene.marks.select { |m| m.kind == :rect && m.attrs[:height] == 6 }
        .map(&:attrs).sort_by { |r| r[:y] }
    end
    let(:lane) do
      edge = bars.first[:x] + bars.first[:width]
      steps.select { |r| r[:x] > edge }
    end

    it "hangs the lane's first step from the top of the fork bar's row" do
      head = lane.min_by { |r| r[:y] }

      expect(head[:y]).to be_within(0.01).of(bars.first[:y])
    end

    it "sets the steps under the fork bar 20 below it" do
      under = steps.reject { |r| lane.include?(r) }

      expect(under.map { |r| r[:y] - (bars.first[:y] + 6) })
        .to all(be_within(0.01).of(20.0))
    end

    it "hangs the lane's last step 6 over the closing diamond" do
      last = lane.max_by { |r| r[:y] }

      expect(diamond(scene).map(&:last).min - (last[:y] + last[:height]))
        .to be_within(0.01).of(6.0)
    end

    it "stacks the rows no taller than the lane's steps need" do
      expect(scene.height).to be < 240.0
    end
  end

  context "with three steps in the lane beside a fork" do
    let(:scene) do
      layout(["if (m?) then (y)", "fork", ":a;", "fork again", ":b;",
              "end fork", "else (n)", ":c;", ":d;", ":e;", "endif"].join("\n"))
    end

    it "leaves the lane's steps on the rows, the fork bar centred on its row" do
      bar = rects(scene).find { |r| r[:height] == 6 }
      top = rects(scene).select { |r| r[:height] > 30 }.map { |r| r[:y] }.min

      expect(bar[:y] - top).to be_within(0.01).of(14.0662)
    end
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
