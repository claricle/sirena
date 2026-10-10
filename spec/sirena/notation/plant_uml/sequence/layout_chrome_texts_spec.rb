# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include PlantUmlSequenceTitleHelpers

  def scene_for(*lines)
    laid_out(*lines, "Alice -> Bob : a long message to widen the page")
  end

  def block(scene, id)
    scene.text_blocks.find { |item| item.id == id }
  end

  it "right-aligns the header on the canvas edge" do
    scene = scene_for("header Top")

    expect(block(scene, "header").texts.first.x).to eq(scene.width)
  end

  it "centres the footer" do
    scene = scene_for("footer Bot")

    expect(block(scene, "footer").texts.first.x).to eq(scene.width / 2)
  end

  it "centres each line of a caption block" do
    scene = scene_for("caption", "One", "Two", "end caption")

    expect(block(scene, "caption").texts.map(&:x).uniq)
      .to eq([scene.width / 2])
  end

  it "draws the footer lines 11.78 apart" do
    ys = block(scene_for("footer", "A", "B", "end footer"), "footer")
      .texts.map(&:y)

    expect(ys.last - ys.first).to be_within(0.01).of(11.78)
  end

  it "draws header and footer in grey at size 10" do
    texts = scene_for("header H", "footer F").text_blocks.flat_map(&:texts)

    expect(texts.map { |t| [t.colour, t.size] }.uniq)
      .to eq([["#888888", 10.0]])
  end

  it "puts the caption above the footer" do
    scene = scene_for("footer F", "caption C")

    expect(block(scene, "caption").texts.first.y)
      .to be < block(scene, "footer").texts.first.y
  end

  it "grows the canvas for a header wider than the diagram" do
    wide = laid_out("header #{'long ' * 40}", "A -> B")

    expect(wide.width).to be > laid_out("A -> B").width
  end
end
