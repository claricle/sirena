# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/class_note_svg"

RSpec.describe Sirena::Renderer::ClassDiagram do
  let(:one) { "classDiagram\nnote \"abc\"\n" }
  let(:two) { "classDiagram\nnote \"x<br />y\"\n" }
  let(:three) { "classDiagram\nnote \"a<br>b<br/>c\"\n" }

  def box_height(source)
    ClassNoteSvg.rect(source, "note-0")["height"].to_f
  end

  def lines(source)
    group = ClassNoteSvg.group(source, "note-0")
    ClassNoteSvg.elements(group, "tspan").map { |run| run.texts.join }
  end

  it "sizes a one-line note as mmdc does" do
    expect(box_height(one)).to eq(36)
  end

  it "grows the box by one line height per extra line" do
    expect(box_height(two)).to eq(60)
  end

  it "grows the box for each <br> spelling" do
    expect(box_height(three)).to eq(84)
  end

  it "draws each line as its own tspan" do
    expect(lines(three)).to eq(%w[a b c])
  end

  it "steps each later line down by one line height" do
    group = ClassNoteSvg.group(three, "note-0")
    baseline = ClassNoteSvg.elements(group, "text").first.attributes["y"]
    runs = ClassNoteSvg.elements(group, "tspan")
    ys = [baseline] + runs.drop(1).map { |run| run.attributes["y"] }
    expect(ys.map(&:to_f).each_cons(2).map { |a, b| b - a }).to eq([24, 24])
  end

  it "leaves the first line on the text baseline" do
    group = ClassNoteSvg.group(three, "note-0")
    first = ClassNoteSvg.elements(group, "tspan").first
    expect(first.attributes["y"]).to be_nil
  end

  it "draws a one-line note without tspans" do
    expect(lines(one)).to be_empty
  end
end
