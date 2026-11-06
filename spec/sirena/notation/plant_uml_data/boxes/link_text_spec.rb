# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUMLData::Boxes::LinkText do
  let(:link) { Struct.new(:label, :tail_text, :head_text) }

  def label_of(start, stop, text = "Label 1")
    described_class.call(link.new(text), start, stop).first
  end

  it "lifts the label of a rising line over the line's far end" do
    mark = label_of([0.0, 100.0], [200.0, 0.0])
    right = mark[:x] + 20.0

    expect(mark[:y]).to be < 100.0 - (right / 2.0)
  end

  it "centres the label of a flat line on its middle" do
    mark = label_of([0.0, 50.0], [200.0, 50.0])

    expect([mark[:anchor], mark[:x]]).to eq(["middle", 102.8])
  end

  it "keeps the label of a flat line off the line" do
    expect(label_of([0.0, 50.0], [200.0, 50.0])[:y]).to be < 50.0
  end

  it "starts the label of a leaning steep line past the line" do
    mark = label_of([100.0, 0.0], [140.0, 200.0])

    expect(mark[:x]).to be > 120.0
  end

  it "draws no label for a link without one" do
    expect(described_class.call(link.new(nil), [0.0, 0.0], [10.0, 90.0]))
      .to eq([])
  end
end
