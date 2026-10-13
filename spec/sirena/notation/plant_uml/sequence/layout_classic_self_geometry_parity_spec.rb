# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:scene) do
    parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
    parsed.transform.new.call(parsed.diagram)
  end
  let(:source) { "@startuml\n#{body}\n@enduml\n" }

  context "with classic self messages in both directions" do
    let(:body) { "A -> A: right\nA <- A: left" }

    let(:dimensions) do
      scene.arrows.map do |arrow|
        coordinates = arrow.path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
        [(coordinates[2] - coordinates[0]).abs,
         coordinates[5] - coordinates[1]]
      end
    end

    it "uses the pinned forty-two-pixel reach and thirteen-pixel drop" do
      expect(dimensions).to eq([[42.0, 13.0], [42.0, 13.0]])
    end
  end

  context "with unlabelled classic self messages after an ordinary message" do
    let(:body) { "A -> B: msg\nA -> A\nB <- B\nB <- B" }

    it "uses fourteen before the first loop and twenty-seven between loops" do
      ys = scene.arrows.map { |arrow| arrow.path[/M \S+ (\S+)/, 1].to_f }
      gaps = ys.each_cons(2).map { |first, second| (second - first).round(4) }

      expect(gaps).to eq([14.0, 27.0, 27.0])
    end
  end

  context "with labelled classic self messages" do
    let(:body) { "A -> A: one\nA -> A: two" }

    it "keeps the labelled cadence separate from the unlabelled cadence" do
      ys = scene.arrows.map { |arrow| arrow.path[/M \S+ (\S+)/, 1].to_f }

      expect(ys.last - ys.first).to be_within(0.0001).of(42.3105)
    end
  end

  context "with ordinary Teoz self messages" do
    let(:body) { "!pragma teoz true\nA -> A: right\nA <- A: left" }

    it "preserves the thirty-six-pixel Teoz reach" do
      reaches = scene.arrows.map do |arrow|
        coordinates = arrow.path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
        (coordinates[2] - coordinates[0]).abs
      end

      expect(reaches).to eq([36.0, 36.0])
    end
  end
end
