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

  # mmdc treats a bare `;` as a statement separator, equivalent to a
  # newline: spec/mermaid/sequence/026_parser_should_handle_semicolons_25
  # compresses a whole diagram onto one line this way and mmdc renders it
  # exactly as the multi-line form.
  describe "#parse bare `;` as a statement separator" do
    it "accepts `;` directly after the sequenceDiagram header" do
      diagram = parser.parse("sequenceDiagram;A->>B: hi")

      expect(diagram.messages.first.message_text).to eq("hi")
    end

    it "splits a message, a note, and a second message joined by `;`" do
      diagram = parser.parse(
        "sequenceDiagram;A->>B: Hello Bob, how are you?;" \
        "Note right of B: B thinks;B-->>A: I am good thanks!;"
      )

      expect(diagram.messages.map(&:message_text))
        .to eq(["Hello Bob, how are you?", "I am good thanks!"])
      expect(diagram.notes.first.text).to eq("B thinks")
      expect(diagram.notes.first.position).to eq("right_of")
    end

    it "does not require a trailing newline after the final `;`" do
      diagram = parser.parse("sequenceDiagram;A->>B: hi;")

      expect(diagram.messages.first.message_text).to eq("hi")
    end

    # The lookahead guard's negative case: a `;` NOT followed by a real
    # statement (or eof) is left as literal text rather than treated as a
    # separator. Mirrors spec/mermaid/sequence/046_parser_should_handle_
    # special_characters_in_notes_45 (note text "-:<>,;# comment", where
    # "# comment" is not a statement), already passing before this change.
    it "leaves a `;` embedded in note text alone when nothing parseable follows it" do
      diagram = parser.parse(
        "sequenceDiagram\nA->>B: hi\nNote right of B: a;# not a statement\n"
      )

      expect(diagram.notes.first.text).to eq("a;# not a statement")
    end

    # The entity guard: `#9829;` is mmdc's HTML entity syntax (renders "♥"),
    # not a separator, mirroring spec/mermaid/sequence/030_spec_diagram_
    # spec_29 (already passing before this change).
    it "does not split message text on an HTML entity's own `;`" do
      diagram = parser.parse("sequenceDiagram\nA->>B: I #9829; you!\n")

      expect(diagram.messages.first.message_text).to eq("I #9829; you!")
    end

    # The case the lookahead alone cannot cover: an entity's `;` sitting
    # right before the real newline. Nothing follows it on the line, so
    # `statement.present? | eof` both fail there too, and only the
    # html_entity alternative keeps the entity's own `;` from being read as
    # the message's trailing terminator (which would drop it).
    it "keeps the entity's `;` when the entity ends the message text" do
      diagram = parser.parse("sequenceDiagram\nA->>B: I love #9829;\n")

      expect(diagram.messages.first.message_text).to eq("I love #9829;")
    end
  end

  # spec/mermaid/sequence/053 and 054: `alt`/`par` with NO label, `;` in
  # place of the newline the label would otherwise end on.
  describe "#parse alt/par with no label, separated by `;`" do
    it "parses an alt block with an empty label" do
      diagram = parser.parse(
        "sequenceDiagram\nA->>B: hi\nalt;B-->>A: ok\nend\n"
      )

      expect(diagram.messages.map(&:message_text)).to eq(%w[hi ok])
    end

    it "parses a par block with an empty label" do
      diagram = parser.parse(
        "sequenceDiagram\nA->>B: hi\npar;B-->>A: ok\nend\n"
      )

      expect(diagram.messages.map(&:message_text)).to eq(%w[hi ok])
    end
  end
end
