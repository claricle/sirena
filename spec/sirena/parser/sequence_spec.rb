# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"

RSpec.describe Sirena::Parser::SequenceParser do
  let(:parser) { described_class.new }

  def message_for(arrow, suffix = "")
    source = if suffix == "-"
               "sequenceDiagram\n    A->>+B: open\n    " \
                 "B#{arrow}#{gap(arrow)}-A: m\n"
             else
               "sequenceDiagram\n    A#{arrow}#{suffix}B: m\n"
             end
    parser.parse(source).messages.last
  end

  # A reversed arrow already ends in a dash, so writing the deactivation
  # suffix against it spells the longer arrow instead: `B//--A` is `//--`,
  # not `//-` closing an activation. mmdc reads it that way too, and takes
  # the spaced form for the deactivation.
  def gap(arrow)
    arrow.end_with?("-") ? " " : ""
  end

  # The whole vocabulary, read off mmdc 11.12.0's own SVG: the line class
  # (messageLine0 solid / messageLine1 dotted), the marker id, and whether
  # it lands on marker-start or marker-end. Reversing a half or stick arrow
  # keeps the head and moves it to the source end.
  def self.arrows
    {
      "->" => %w[solid none target],
      "-->" => %w[dotted none target],
      "->>" => %w[solid filled target],
      "-->>" => %w[dotted filled target],
      "-x" => %w[solid cross target],
      "--x" => %w[dotted cross target],
      "-X" => %w[solid cross target],
      "--X" => %w[dotted cross target],
      "-)" => %w[solid open target],
      "--)" => %w[dotted open target],
      "-|/" => %w[solid half_bottom target],
      "--|/" => %w[dotted half_bottom target],
      "-|\\" => %w[solid half_top target],
      "--|\\" => %w[dotted half_top target],
      "-//" => %w[solid stick_bottom target],
      "--//" => %w[dotted stick_bottom target],
      "-\\\\" => %w[solid stick_top target],
      "--\\\\" => %w[dotted stick_top target],
      "/|-" => %w[solid half_bottom source],
      "/|--" => %w[dotted half_bottom source],
      "\\|-" => %w[solid half_top source],
      "\\|--" => %w[dotted half_top source],
      "//-" => %w[solid stick_bottom source],
      "//--" => %w[dotted stick_bottom source],
      "\\\\-" => %w[solid stick_top source],
      "\\\\--" => %w[dotted stick_top source],
      "<<->>" => %w[solid filled both],
      "<<-->>" => %w[dotted filled both]
    }.freeze
  end

  describe "#parse arrow set" do
    arrows.each do |arrow, (line_style, head_style, head_side)|
      it "parses #{arrow} as #{line_style}/#{head_style} on the #{head_side}" do
        message = message_for(arrow)

        expect(
          [message.line_style, message.head_style, message.head_side]
        ).to eq([line_style, head_style, head_side])
      end

      # A mis-read arrow still parses — the leftover characters just land
      # in an actor name — so the styles alone cannot catch it.
      it "leaves the participants of #{arrow} alone" do
        message = message_for(arrow)

        expect([message.from_id, message.to_id]).to eq(%w[A B])
      end
    end

    it "puts a head on both ends only for the << >> arrows" do
      both = self.class.arrows.keys.select { |a| message_for(a).bidirectional? }

      expect(both).to eq(["<<->>", "<<-->>"])
    end

    it "puts a head on the source end only for the reversed spellings" do
      source_end = self.class.arrows.keys.select do |a|
        message_for(a).head_side == "source"
      end

      expect(source_end).to eq(["/|-", "/|--", "\\|-", "\\|--",
                                "//-", "//--", "\\\\-", "\\\\--"])
    end

    # mmdc reads `A->|B` as `->` into an actor named `|B`. Treating the
    # pipe as part of the arrow named participant `B` instead, so the
    # message pointed at the wrong lifeline while looking correct.
    ["->|", "-->|"].each do |not_an_arrow|
      it "does not read #{not_an_arrow} as an arrow" do
        source = "sequenceDiagram\n    A#{not_an_arrow}B: m\n"

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "#parse activation suffixes" do
    arrows.each_key do |arrow|
      it "accepts #{arrow} with an activation suffix" do
        expect(message_for(arrow, "+").head_style)
          .to eq(message_for(arrow).head_style)
      end

      it "accepts #{arrow} with a deactivation suffix" do
        expect(message_for(arrow, "-").head_style)
          .to eq(message_for(arrow).head_style)
      end
    end

    it "reads a reversed arrow whole rather than as a deactivation" do
      # `B//--A` has to be the `//--` arrow. Reading it as `//-` plus a
      # closing dash both draws the wrong head and closes an activation
      # mermaid leaves open. An activation is only recorded once it closes,
      # so an empty list is the proof that nothing closed it.
      source = "sequenceDiagram\n    A->>+B: open\n    B//--A: m\n"
      diagram = parser.parse(source)

      expect(diagram.messages.last.head_style).to eq("stick_bottom")
      expect(diagram.activations).to be_empty
    end

    it "allows whitespace before the suffix" do
      # mmdc renders `A-x + B`, and requiring the suffix to touch the arrow
      # rejected every spaced form.
      source = "sequenceDiagram\n    A->> + B: open\n    B-->> - A: close\n"

      expect(parser.parse(source).activations.size).to eq(1)
    end

    it "opens an activation on + and closes it on -" do
      # An activation record is only emitted once it closes, so the pair
      # has to be written out.
      source = "sequenceDiagram\n    A->>+B: open\n    B-->>-A: close\n"

      diagram = parser.parse(source)

      expect(diagram.activations.map(&:participant_id)).to eq(["B"])
    end

    it "carries the suffix on arrows that never had one before" do
      source = "sequenceDiagram\n    A-x+B: open\n    B--)-A: close\n"

      diagram = parser.parse(source)

      expect(diagram.activations.map(&:participant_id)).to eq(["B"])
    end
  end

  describe "#parse deactivation" do
    it "closes the most recent activation still open" do
      # Two opens then two closes is ordinary mermaid. Reading only the
      # last entry closed the same activation twice.
      source = <<~MERMAID
        sequenceDiagram
            A->>+B: one
            A->>+B: two
            B-->>-A: close one
            B-->>-A: close two
      MERMAID

      # The count alone passes with FIFO too: two opens and two closes
      # give two activations either way. The end indexes are the tell —
      # LIFO closes the inner one first.
      spans = parser.parse(source).activations.map do |a|
        [a.participant_id, a.start_index, a.end_index]
      end

      expect(spans).to eq([["B", 1, 2], ["B", 0, 3]])
    end

    it "closes the most recent when two participants interleave" do
      source = <<~MERMAID
        sequenceDiagram
            A->>+B: open b
            B->>+C: open c
            C-->>-B: close c
            B-->>-A: close b
      MERMAID

      spans = parser.parse(source).activations.map do |a|
        [a.participant_id, a.start_index, a.end_index]
      end

      expect(spans).to eq([["C", 1, 2], ["B", 0, 3]])
    end

    it "rejects deactivating a participant with nothing open" do
      # mmdc refuses this, and ignoring it silently rendered every arrow
      # form carrying an unmatched `-`.
      expect { parser.parse("sequenceDiagram\n    A-x-B: close\n") }
        .to raise_error(Sirena::Parser::ParseError, /inactive participant/)
    end
  end

  describe "#parse forms mermaid rejects" do
    # mmdc 11.12.0 rejects every one of these. The first two parsed before
    # the arrow set was rewritten, so they are demotions we want. The last
    # three are the check that the wider vocabulary did not become
    # "anything with a dash in it".
    ['->)', '-->)', '--->', '---)', '--@#$', '--|', '-|'].each do |arrow|
      it "rejects #{arrow}" do
        source = "sequenceDiagram\n    A#{arrow}B: m\n"

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "#parse alternation order" do
    # Parslet alternation is first-match, so a shorter arrow listed before a
    # longer one that starts with it wins and the rest of the token becomes
    # part of the actor name. Only genuine prefix pairs can shadow: -> is a
    # prefix of ->>, and --> of -->>. <<->> and <<-->> diverge on their third
    # character, so pairing those tests nothing.
    {
      "->" => "->>",
      "-->" => "-->>"
    }.each do |shorter, longer|
      it "reads #{longer} whole rather than #{shorter} plus a stray >" do
        expect(message_for(longer).head_style).to eq("filled")
        expect(message_for(shorter).head_style).to eq("none")
      end
    end

    # The reversed spellings shadow the same way, with the dash on the
    # other side: `//-` listed first takes the head of `//--` and leaves
    # the trailing dash to be read as a deactivation.
    {
      "//-" => "//--",
      "\\\\-" => "\\\\--",
      "/|-" => "/|--",
      "\\|-" => "\\|--"
    }.each do |shorter, longer|
      it "reads #{longer} whole rather than #{shorter} plus a stray -" do
        expect(message_for(longer).line_style).to eq("dotted")
        expect(message_for(shorter).line_style).to eq("solid")
        expect(message_for(longer).to_id).to eq("B")
      end
    end

    it "keeps the actor names intact when the longer arrow wins" do
      # The tell for a mis-ordered alternation: the arrow still parses, but
      # the leftover > lands in the target's name.
      message = message_for("-->>")

      expect(message.from_id).to eq("A")
      expect(message.to_id).to eq("B")
    end
  end
end
