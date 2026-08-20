# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"

RSpec.describe Sirena::Parser::SequenceParser do
  let(:parser) { described_class.new }

  def message_for(arrow, suffix = "")
    source = if suffix == "-"
               "sequenceDiagram\n    A->>+B: open\n    B#{arrow}-A: m\n"
             else
               "sequenceDiagram\n    A#{arrow}#{suffix}B: m\n"
             end
    parser.parse(source).messages.last
  end

  describe "#parse arrow set" do
    # Each row is verified against mmdc 11.12.0: the line class it emits
    # (messageLine0 solid / messageLine1 dotted), whether it emits a
    # marker-end, and whether it also emits a marker-start.
    {
      "->" => %w[solid none],
      "-->" => %w[dotted none],
      "->|" => %w[solid none],
      "-->|" => %w[dotted none],
      "->>" => %w[solid filled],
      "-->>" => %w[dotted filled],
      "-x" => %w[solid cross],
      "--x" => %w[dotted cross],
      "-X" => %w[solid cross],
      "--X" => %w[dotted cross],
      "-)" => %w[solid open],
      "--)" => %w[dotted open],
      "-|/" => %w[solid half_bottom],
      "--|/" => %w[dotted half_bottom],
      "-|\\" => %w[solid half_top],
      "--|\\" => %w[dotted half_top],
      "<<->>" => %w[solid filled],
      "<<-->>" => %w[dotted filled]
    }.each do |arrow, (line_style, head_style)|
      it "parses #{arrow} as #{line_style}/#{head_style}" do
        message = message_for(arrow)

        expect(message.line_style).to eq(line_style)
        expect(message.head_style).to eq(head_style)
      end
    end

    it "marks only the << >> arrows bidirectional" do
      arrows = %w[-> --> ->| -->| ->> -->> -x --x -X --X -) --)
                  -|/ --|/ -|\\ --|\\ <<->> <<-->>]
      bidirectional = arrows.select { |a| message_for(a).bidirectional }

      expect(bidirectional).to eq(["<<->>", "<<-->>"])
    end
  end

  describe "#parse activation suffixes" do
    %w[-> --> ->| -->| ->> -->> -x --x -X --X -) --)
       -|/ --|/ -|\\ --|\\ <<->> <<-->>].each do |arrow|
      it "accepts #{arrow} with an activation suffix" do
        expect(message_for(arrow, "+").head_style)
          .to eq(message_for(arrow).head_style)
      end

      it "accepts #{arrow} with a deactivation suffix" do
        expect(message_for(arrow, "-").head_style)
          .to eq(message_for(arrow).head_style)
      end
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

      expect(parser.parse(source).activations.size).to eq(2)
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

    it "keeps the actor names intact when the longer arrow wins" do
      # The tell for a mis-ordered alternation: the arrow still parses, but
      # the leftover > lands in the target's name.
      message = message_for("-->>")

      expect(message.from_id).to eq("A")
      expect(message.to_id).to eq("B")
    end
  end
end
