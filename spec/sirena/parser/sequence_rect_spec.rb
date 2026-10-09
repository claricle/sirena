# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"

RSpec.describe Sirena::Parser::Sequence do
  subject(:diagram) { described_class.new.parse(source) }

  let(:senders) { diagram.messages.map(&:from_id) }

  context "with a colour function and no trailing newline" do
    let(:source) do
      "sequenceDiagram\nAlice->Bob: Hello\nrect rgb(0, 0, 0)\n" \
        "Bob->Alice: dark\nend"
    end

    it "keeps the messages inside the block" do
      expect(senders).to eq(%w[Alice Bob])
    end
  end

  context "when nested" do
    let(:source) do
      "sequenceDiagram\nrect red\nrect blue\nA->B: x\nend\nB->A: y\nend\n"
    end

    it "keeps messages from both levels" do
      expect(senders).to eq(%w[A B])
    end
  end

  context "when a participant is called rect" do
    let(:source) { "sequenceDiagram\nrect->>B: x\nB->>rect: y\n" }

    it "still reads a message" do
      expect(senders).to eq(%w[rect B])
    end
  end

  it "rejects an unclosed rect, as mermaid does" do
    expect do
      described_class.new.parse("sequenceDiagram\nrect red\nA->B: x\n")
    end.to raise_error(Sirena::Parser::ParseError)
  end
end
