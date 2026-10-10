# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/class_note_svg"

RSpec.describe Sirena::Renderer::ClassDiagram do
  let(:source) do
    "classDiagram\nclass MyClass\nnote \"a general note\"\n" \
      "note for MyClass \"a class note\"\n"
  end

  it "draws the text of a general note" do
    expect(ClassNoteSvg.texts(source)).to include("a general note")
  end

  it "draws the text of a note for a class" do
    expect(ClassNoteSvg.texts(source)).to include("a class note")
  end

  it "draws each note as its own group" do
    expect(ClassNoteSvg.notes(source).length).to eq(2)
  end

  it "fills a note yellow, as mmdc does" do
    expect(ClassNoteSvg.values(source, "rect", "fill")).to include("#fff5ad")
  end

  it "joins a note for a class to it with a dashed line" do
    lines = ClassNoteSvg.notes(source).flat_map do |group|
      ClassNoteSvg.elements(group, "line")
    end
    expect(lines.map { |line| line.attributes["stroke-dasharray"] })
      .to eq(["2,2"])
  end

  it "draws no note group when the source has no note" do
    expect(ClassNoteSvg.notes("classDiagram\nclass A\n")).to be_empty
  end

  it "keeps a class where it was when a note is added" do
    bare = ClassNoteSvg.document("classDiagram\nclass A\n")
    noted = ClassNoteSvg.document("classDiagram\nclass A\nnote \"n\"\n")
    expect(class_rect(noted)).to eq(class_rect(bare))
  end

  def class_rect(doc)
    group = ClassNoteSvg.elements(doc, "g").find do |item|
      item.attributes["id"] == "class-A"
    end
    ClassNoteSvg.elements(group, "rect").first.attributes.to_h
  end
end
