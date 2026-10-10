# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::ClassNotes do
  def notes_of(source)
    Sirena::Parser::ClassDiagram.new.parse(source).notes
  end

  it "reads a general note without a target" do
    notes = notes_of("classDiagram\nnote \"hello\"\n")
    expect(notes.map { |n| [n.text, n.target_id] }).to eq([["hello", nil]])
  end

  it "reads the class a note is for" do
    notes = notes_of("classDiagram\nclass A\nnote for A \"hi\"\n")
    expect(notes.first.target_id).to eq("A")
  end

  it "keeps notes in source order" do
    notes = notes_of("classDiagram\nnote \"one\"\nnote \"two\"\n")
    expect(notes.map(&:text)).to eq(%w[one two])
  end

  it "shows a tag as its content, as mmdc does" do
    notes = notes_of("classDiagram\nnote \"<b>bold</b> text\"\n")
    expect(notes.first.text).to eq("bold text")
  end

  it "leaves a note for a class that does not exist unattached" do
    notes = notes_of("classDiagram\nnote for Ghost \"x\"\n")
    expect(notes.first.target_id).to be_nil
  end
end
