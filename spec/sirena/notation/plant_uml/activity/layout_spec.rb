# frozen_string_literal: true

require "spec_helper"
require_relative "activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity::Layout do
  include ActivityHelpers

  def marks(scene, kind)
    scene.marks.select { |m| m.kind == kind }
  end

  def action_rect(scene, text)
    index = scene.marks.index do |m|
      m.kind == :text && m.attrs[:content] == text
    end
    scene.marks[0...index].reverse.find { |m| m.kind == :rect }.attrs
  end

  it "stacks a straight flow top to bottom in one column",
     :aggregate_failures do
    scene = layout("start\n:a;\n:b;\nstop")
    a = action_rect(scene, "a")
    b = action_rect(scene, "b")

    expect(b[:y]).to be > a[:y] + a[:height]
    expect(b[:x] + (b[:width] / 2)).to eq(a[:x] + (a[:width] / 2))
  end

  it "puts a second branch to the right of the first" do
    scene = layout("if (x?) then (y)\n:left;\nelse (n)\n:right;\nendif")

    expect(action_rect(scene,
                       "right")[:x]).to be > action_rect(scene, "left")[:x] + 20
  end

  it "keeps a loop's exit below the loop body" do
    scene = layout("while (more?)\n:work;\n:more work;\nendwhile\n:after;")

    expect(action_rect(scene,
                       "after")[:y]).to be > action_rect(scene, "more work")[:y]
  end

  it "stretches a fork bar over its branches" do
    scene = layout("fork\n:a;\nfork again\n:b;\nend fork")
    bar = marks(scene, :rect).find { |m| m.attrs[:role] == :bar }.attrs

    expect(bar[:width]).to be > action_rect(scene,
                                            "b")[:x] - action_rect(scene,
                                                                   "a")[:x]
  end

  it "keeps every mark inside the canvas, including a loop edge",
     :aggregate_failures do
    scene = layout("repeat\n:a;\n:b;\nrepeat while (again?)\n:c;")
    points = marks(scene, :path).flat_map { |m| m.attrs[:points] }

    expect(points.map(&:first).min).to be >= 0
    expect(points.map(&:first).max).to be <= scene.width
    expect(points.map(&:last).max).to be <= scene.height
  end

  it "leaves room on the left for a note" do
    scene = layout(":a;\nnote left: a long note here")
    note = marks(scene, :polygon).find { |m| m.attrs[:fill] == "#FEFFDD" }

    expect(note.attrs[:points].map(&:first).min).to be >= 0
  end

  it "gives each swimlane its own band, in order", :aggregate_failures do
    scene = layout("|One|\n:a;\n|Two|\n:b;")
    first = action_rect(scene, "a")

    expect(action_rect(scene, "b")[:x]).to be > first[:x] + first[:width]
    expect(scene.marks.map { |m| m.attrs[:content] }).to include("One", "Two")
  end

  it "draws a partition frame around its nodes", :aggregate_failures do
    scene = layout("partition P {\n:a;\n}")
    frame = marks(scene, :rect).first.attrs
    inner = action_rect(scene, "a")

    expect(frame[:x]).to be < inner[:x]
    expect(frame[:y] + frame[:height]).to be > inner[:y] + inner[:height]
  end

  it "gives the same scene for the same source" do
    source = "start\nif (x?) then (y)\n:a;\nelse\n:b;\nendif\nstop"
    first = layout(source)
    second = layout(source)

    expect(first.marks.map(&:attrs)).to eq(second.marks.map(&:attrs))
  end
end
