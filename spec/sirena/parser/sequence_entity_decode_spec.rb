# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"

# Texts measured with mmdc: character references are decoded in the
# text drawn for an actor (alias or id) and in notes; ids stay as written.
module SequenceEntityHelpers
  def parse_diagram(body)
    described_class.new.parse("sequenceDiagram\n#{body}\n")
  end

  def label_of(body, id)
    parse_diagram(body).find_participant(id).label
  end
end

RSpec.describe Sirena::Parser::Sequence do
  include SequenceEntityHelpers

  {
    "participant A as \"x#59;y\"" => "\"x;y\"",
    "participant A as p#amp;q#65;r" => "p&qAr",
    "participant A as #lt;b#gt;" => "<b>",
    "participant A as a#x41;b#foo;" => "a&x41;b&foo;",
    "actor A as d#59;e" => "d;e",
    "create participant A as c#59;d" => "c;d",
  }.each do |declaration, expected|
    it "decodes the alias of #{declaration.inspect}" do
      body = "#{declaration}\nB->>A: hi"
      expect(label_of(body, "A")).to eq(expected)
    end
  end

  it "decodes a bare actor id used as its own label" do
    expect(label_of("participant K#65;", "K#65;")).to eq("KA")
  end

  it "decodes the label of an actor named only by a message" do
    expect(label_of("K#65;->>B: hi", "K#65;")).to eq("KA")
  end

  it "keeps an id as written, as mmdc keeps two actors" do
    diagram = parse_diagram("participant EA\nE#65;->>B: hi")

    expect(diagram.participants.map(&:id)).to eq(%w[EA E#65; B])
  end

  it "decodes the text of a note" do
    diagram = parse_diagram("Note over A: n#59;1 #amp;")

    expect(diagram.notes.first.text).to eq("n;1 &")
  end

  it "reads a note's actor name with a reference in it" do
    diagram = parse_diagram("Note over A#65;: n")

    expect(diagram.notes.first.participant_ids).to eq(%w[A#65;])
  end

  it "leaves message text for display to decode once" do
    diagram = parse_diagram("A->>B: #35;59")

    expect(diagram.messages.first.message_text).to eq("#35;59")
  end

  it "reads an activate target with a reference in it" do
    diagram = parse_diagram("activate K#65;\nB->>B: hi")

    expect(diagram.participants.map(&:id)).to eq(%w[K#65; B])
  end
end
