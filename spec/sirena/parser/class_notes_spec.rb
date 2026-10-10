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

  it "starts a new line at each <br> spelling, as mmdc does" do
    notes = notes_of("classDiagram\nnote \"a<br>b<br/>c<br />d\"\n")
    expect(notes.first.text).to eq("a\nb\nc\nd")
  end

  it "keeps a literal backslash-n as text, as mmdc does" do
    notes = notes_of("classDiagram\nnote \"a\\nb\"\n")
    expect(notes.first.text).to eq("a\\nb")
  end

  it "leaves a note for a class that does not exist unattached" do
    notes = notes_of("classDiagram\nnote for Ghost \"x\"\n")
    expect(notes.first.target_id).to be_nil
  end

  it "resolves a unique dotted class from its unqualified note target" do
    notes = notes_of("classDiagram\nclass Pkg.A\nnote for A \"about A\"\n")
    expect(notes.first.target_id).to eq("Pkg.A")
  end
end
