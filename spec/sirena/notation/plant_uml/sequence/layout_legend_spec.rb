# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include PlantUmlSequenceTitleHelpers

  def legend_for(place, *body)
    laid_out("legend #{place}".strip, *body, "end legend",
             "Alice -> Bob : a long message to widen the page").legend
  end

  it "widens the box with the text" do
    expect(legend_for("", "Hello world").width)
      .to be > legend_for("", "Hello").width
  end

  it "starts the box 12 from the left edge for left" do
    expect(legend_for("left", "Hello").x).to eq(12.0)
  end

  it "ends the box 12 from the right edge for right" do
    scene = laid_out("legend right", "Hello", "end legend", "Alice -> Bob")

    expect(scene.width - (scene.legend.x + scene.legend.width)).to eq(12.0)
  end

  it "indents the legend text by 5" do
    legend = legend_for("left", "Hello")

    expect(legend.texts.first.x).to eq(legend.x + 5)
  end

  it "left-aligns every line of the text" do
    legend = legend_for("", "Hello", "World wide")

    expect(legend.texts.map(&:x).uniq.size).to eq(1)
  end

  it "puts a top legend above the participants" do
    legend = legend_for("top", "Hello")

    expect(legend.y).to be < 40
  end

  it "has no legend when none is written" do
    expect(laid_out("A -> B").legend).to be_nil
  end
end
