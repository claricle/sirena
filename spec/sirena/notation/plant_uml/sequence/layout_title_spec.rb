# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include PlantUmlSequenceTitleHelpers

  let(:plain) { laid_out("A -> B") }
  let(:titled) { laid_out("title Hello", "A -> B") }

  it "draws the title text" do
    expect(titled.title.texts.map(&:content)).to eq(["Hello"])
  end

  it "centres the title on the canvas" do
    expect(titled.title.texts.first.x).to eq(titled.width / 2)
  end

  it "pushes the rows down by the title's room" do
    expect(first_arrow_y(titled) - first_arrow_y(plain)).to be_within(0.001).of(37.49)
  end

  it "grows the canvas for a title wider than the diagram" do
    wide = laid_out("title #{'long ' * 30}", "A -> B")

    expect(wide.width).to be > plain.width
  end

  it "draws no title when none is written" do
    expect(plain.title).to be_nil
  end
end
