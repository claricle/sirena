# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence do
  let(:source) do
    <<~MERMAID
      sequenceDiagram
          participant A
          participant B
          A->>B: first
          Note over A,B: line one<br>line two
          B->>A: second
          Note right of B: tail
    MERMAID
  end
  let(:scene) do
    described_class.new.to_graph(Sirena::Parser::Sequence.new.parse(source))
  end
  let(:plain) do
    text = source.lines.grep_v(/Note/).join
    described_class.new.to_graph(Sirena::Parser::Sequence.new.parse(text))
  end
  let(:first_note) { scene.notes.first }
  let(:rows) { scene.messages.map { |message| message.shaft.y1 } }

  it "places a note per source note" do
    expect(scene.notes.length).to eq(2)
  end

  it "splits <br> into one label per line" do
    expect(first_note.lines.map(&:text)).to eq(["line one", "line two"])
  end

  it "puts the note below the message before it" do
    expect(first_note.y).to be > rows.first
  end

  it "puts the note above the message after it" do
    expect(first_note.y + first_note.height).to be < rows.last
  end

  it "pushes later messages down by the note slot" do
    expect(rows.last - plain.messages.last.shaft.y1).to eq(first_note.height + 20)
  end

  it "leaves earlier messages where they were" do
    expect(rows.first).to eq(plain.messages.first.shaft.y1)
  end

  it "keeps a trailing note inside the canvas height" do
    expect(scene.notes.last.y + scene.notes.last.height)
      .to be < scene.height
  end

  it "keeps a right-of note inside the canvas width" do
    expect(scene.notes.last.x + scene.notes.last.width).to be < scene.width
  end

  it "spans both participants of an over-note" do
    centers = scene.lifelines.map(&:x1)
    expect(first_note.x).to be < centers.min
  end

  it "grows the lifelines for the note slots" do
    expect(scene.lifelines.first.y2).to be > plain.lifelines.first.y2
  end
end
