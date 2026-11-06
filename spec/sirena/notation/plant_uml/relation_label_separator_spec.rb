# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::RelationLabelSeparator do
  let(:text_class) { Struct.new(:role, :content, :x, :y, :anchor) }
  let(:scene_class) { Struct.new(:texts) }
  let(:labels) do
    Array.new(60) do
      text_class.new("relation_label", "label", 50.0, 80.0, "middle")
    end
  end

  it "returns a label to its own line when no free line remains" do
    separator = described_class.new(size: 12, width_of: ->(s) { s.length * 6 })

    separator.call([scene_class.new(labels)])

    expect(labels.last.y).to eq(80.0)
  end

  context "with the lines of the relations" do
    let(:line_class) { Struct.new(:texts, :path, :stroke_width) }
    let(:separator) do
      described_class.new(size: 12, width_of: ->(s) { s.length * 6 })
    end

    def label_at(x_pos, y_pos)
      text_class.new("relation_label", "label", x_pos, y_pos, "middle")
    end

    it "moves a label off the line of another relation" do
      label = label_at(100.0, 50.0)
      own = line_class.new([label], "M 0 100 L 200 0", 1.0)
      across = line_class.new([], "M 0 45 L 200 45", 2.0)

      separator.call([own, across])

      expect([label.x, label.y]).not_to eq([100.0, 50.0])
    end

    it "keeps a label that no other line runs through" do
      label = label_at(100.0, 50.0)
      own = line_class.new([label], "M 0 300 L 200 300", 1.0)
      far = line_class.new([], "M 0 300 L 200 300", 2.0)

      separator.call([own, far])

      expect([label.x, label.y]).to eq([100.0, 50.0])
    end

    it "slides a label along its own line to clear a line across it" do
      label = label_at(100.0, 50.0)
      own = line_class.new([label], "M 0 0 L 200 0", 1.0)
      across = line_class.new([], "M 100 -500 L 100 500", 2.0)

      separator.call([own, across])

      expect(label.x).not_to eq(100.0)
    end

    it "leaves a label where it was when no spot is clear" do
      label = label_at(100.0, 50.0)
      own = line_class.new([label], "M 0 0 L 200 0", 1.0)

      separator.call([own, *walls])

      expect([label.x, label.y]).to eq([100.0, 50.0])
    end

    def walls
      Array.new(21) do |index|
        line_class.new([], "M #{index * 10} -5000 L #{index * 10} 5000", 4.0)
      end
    end
  end
end
