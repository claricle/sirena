# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"

# Texts measured with mmdc: character references are decoded in actor
# ids, `as` aliases and notes before anything is drawn.
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
    expect(label_of("participant K#65;", "KA")).to eq("KA")
  end

  it "treats a referenced and a decoded id as one actor" do
    diagram = parse_diagram("participant E#65;\nEA->>B: hi")

    expect(diagram.participants.map(&:id)).to eq(%w[EA B])
  end

  it "decodes the text of a note" do
    diagram = parse_diagram("Note over A: n#59;1 #amp;")

    expect(diagram.notes.first.text).to eq("n;1 &")
  end

  it "decodes a note's actor ids" do
    diagram = parse_diagram("Note over A#65;: n")

    expect(diagram.notes.first.participant_ids).to eq(%w[AA])
  end

  it "leaves message text for display to decode once" do
    diagram = parse_diagram("A->>B: #35;59")

    expect(diagram.messages.first.message_text).to eq("#35;59")
  end

  it "decodes an id in activate" do
    diagram = parse_diagram("activate K#65;\nKA->>B: hi")

    expect(diagram.participants.map(&:id)).to eq(%w[KA B])
  end
end
