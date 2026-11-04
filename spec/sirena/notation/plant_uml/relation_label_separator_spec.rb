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
end
