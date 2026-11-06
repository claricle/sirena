# frozen_string_literal: true

require "spec_helper"
require_relative "activity_helpers"

# The legacy `(*)` syntax laid out as PlantUML does: an arrow that lies along
# its row puts both ends on one row, and a long edge goes round what it would
# cross. Fixtures plantuml-lrg-5-4 and 5-12 are the oracle.
RSpec.describe Sirena::Notation::PlantUML::Activity::Layout do
  include ActivityHelpers

  def scene_of(id)
    path = File.join(ActivityHelpers::FIXTURES, "plantuml-lrg-#{id}.puml")
    body = File.read(path).sub(/\A@startuml\n/, "").sub(/@enduml\s*\z/, "")
    layout(body)
  end

  def rect_of(scene, text)
    index = scene.marks.index do |m|
      m.kind == :text && m.attrs[:content] == text
    end
    scene.marks[0...index].reverse.find { |m| m.kind == :rect }.attrs
  end

  def middle(rect)
    rect[:y] + (rect[:height] / 2.0)
  end

  def overlap?(points, axis, start, size)
    values = points.map { |point| point[axis] }
    values.min < start + size - 2 && values.max > start + 2
  end

  # Whether a segment runs inside the rect (its own border does not count).
  def crosses?(rect, segment)
    overlap?(segment, 0, rect[:x], rect[:width]) &&
      overlap?(segment, 1, rect[:y], rect[:height])
  end

  describe "plantuml-lrg-5-4" do
    let(:scene) { scene_of("5-4") }
    let(:stop) { scene.marks.select { |m| m.kind == :circle }.last.attrs }

    it "ends beside Another Action, to its right", :aggregate_failures do
      another = rect_of(scene, "Another Action")

      expect(stop[:cy]).to be_within(0.5).of(middle(another))
      expect(stop[:cx]).to be > another[:x] + another[:width]
    end

    it "puts Something else on the decision's row, to the right" do
      expect(middle(rect_of(scene, "Something else")))
        .to be < middle(rect_of(scene, "Some Action"))
    end

    it "draws no edge through Another Action" do
      another = rect_of(scene, "Another Action")
      crossing = scene.marks.select { |m| m.kind == :path }.select do |m|
        m.attrs[:points].each_cons(2).any? { |seg| crosses?(another, seg) }
      end
      expect(crossing).to be_empty
    end
  end

  describe "plantuml-lrg-5-12" do
    let(:diagram) do
      path = File.join(ActivityHelpers::FIXTURES, "plantuml-lrg-5-12.puml")
      Sirena::Notation::PlantUML::Activity::Parser.new.parse(File.read(path))
    end

    it "has no loop: the next test is fed by the last branch only",
       :aggregate_failures do
      post = diagram.nodes.find { |n| n.text == "is Post?" }

      expect(diagram.edges.count { |e| e.to.equal?(post) }).to eq(1)
      expect(diagram.edges.find { |e| e.to.text == "Do redirect?" }
        .from.text).to eq("REDIRECT_CHECK")
    end

    it "keeps one bar per name" do
      expect(diagram.nodes.count { |n| n.kind == :bar }).to eq(3)
    end

    it "lays the left-hand branch of a decision left of it",
       :aggregate_failures do
      scene = scene_of("5-12")
      forward = rect_of(scene, "Forward request")
      template = rect_of(scene, "Render page template")

      expect(forward[:x]).to be < template[:x]
      expect(middle(forward)).to be_within(0.5).of(middle(template))
    end
  end
end
