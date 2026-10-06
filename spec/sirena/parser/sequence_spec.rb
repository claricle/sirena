# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"
require "rexml/document"

module SequenceSpecHelpers
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

  module_function

  # The whole vocabulary, read off mmdc 11.12.0's own SVG: the line class
  # (messageLine0 solid / messageLine1 dotted), the marker id, and whether
  # it lands on marker-start or marker-end. Reversing a half or stick arrow
  # keeps the head and moves it to the source end.
  def arrows
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
      "<<-->>" => %w[dotted filled both],
    }.freeze
  end
end

RSpec.describe Sirena::Parser::Sequence do
  include SequenceSpecHelpers

  let(:parser) { described_class.new }

  describe "#parse arrow set" do
    SequenceSpecHelpers.arrows.each do |arrow, (line_style, head_style, head_side)|
      it "parses #{arrow} as #{line_style}/#{head_style} on the #{head_side}" do
        message = message_for(arrow)

        expect(
          [message.line_style, message.head_style, message.head_side],
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
      both = SequenceSpecHelpers.arrows.keys.select { |a| message_for(a).bidirectional? }

      expect(both).to eq(["<<->>", "<<-->>"])
    end

    it "puts a head on the source end only for the reversed spellings" do
      source_end = SequenceSpecHelpers.arrows.keys.select do |a|
        message_for(a).head_side == "source"
      end

      expect(source_end).to eq(["/|-", "/|--", "\\|-", "\\|--",
                                "//-", "//--", "\\\\-", "\\\\--"])
    end

    # mmdc reads `A->|B` as `->` into an actor named `|B`. Treating the
    # pipe as part of the arrow named participant `B` instead, so the
    # message pointed at the wrong lifeline while looking correct. A
    # leading `|` on a message endpoint is ordinary actor-name material
    # (see `message_actor_lead`), so the fix is that `->` stays a 2-char
    # arrow and the recipient is literally `|B`, matching mmdc — not that
    # the line is rejected.
    ["->|", "-->|"].each do |not_an_arrow|
      it "does not read #{not_an_arrow} as an arrow, matching mmdc" do
        source = "sequenceDiagram\n    A#{not_an_arrow}B: m\n"

        expect(parser.parse(source).participants.map(&:id)).to eq(%w[A |B])
      end
    end
  end

  describe "#parse activation suffixes" do
    SequenceSpecHelpers.arrows.each_key do |arrow|
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
    ["->)", "-->)", "--->", "---)", '--@#$', "--|", "-|"].each do |arrow|
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
      "-->" => "-->>",
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
      "\\|-" => "\\|--",
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

  describe "#parse header semicolon" do
    it "accepts a semicolon directly after sequenceDiagram with no space" do
      diagram = parser.parse("sequenceDiagram;Alice->>Bob: hi\n")

      expect(diagram.messages.last.to_id).to eq("Bob")
    end

    it "accepts a semicolon then a space after sequenceDiagram" do
      diagram = parser.parse("sequenceDiagram; Alice->>Bob: hi\n")

      expect(diagram.messages.last.to_id).to eq("Bob")
    end
  end

  describe "#parse inline semicolons as statement separators" do
    it "splits a message's text at an inline semicolon" do
      diagram = parser.parse("sequenceDiagram\nA->>B: hi;A->>B: bye\n")

      expect(diagram.messages.map(&:message_text)).to eq(%w[hi bye])
    end

    it "treats a doubled inline semicolon as an empty statement, not a syntax error" do
      # Guards `statements`' tolerance for a bare `;` with nothing between
      # it and the previous one: reverting to `(statement >> ws?).repeat(1)`
      # turns this red (mermaid 11.16.1 accepts it, giving 2 messages).
      diagram = parser.parse("sequenceDiagram\nAlice->>Bob: m;;Alice->>Bob: m2\n")

      expect(diagram.messages.map(&:message_text)).to eq(%w[m m2])
    end

    it "splits a note's text at an inline semicolon" do
      diagram = parser.parse(
        "sequenceDiagram\nnote right of A: thinking;A->>B: hi\n",
      )

      expect(diagram.notes.last.text).to eq("thinking")
    end

    it "matches case 026's full shape: two messages and one note" do
      source = File.read(
        File.expand_path(
          "../../mermaid/sequence/026_parser_should_handle_semicolons_25.mmd", __dir__
        ),
      )

      diagram = parser.parse(source)

      expect(diagram.messages.map(&:message_text))
        .to eq(["Hello Bob, how are you?", "I am good thanks!"])
      expect(diagram.notes.map(&:text)).to eq(["Bob thinks"])
    end

    it "keeps a character reference in message text intact, not split at its semicolon" do
      diagram = parser.parse("sequenceDiagram\nA->>B: I #9829; you!;A->>C: bye\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([["A", "B", "I #9829; you!"], %w[A C bye]])
    end

    it "treats a trailing # comment on message text as running to line end, ; included" do
      diagram = parser.parse("sequenceDiagram\nA->>B: hi # c; B->>C: yo\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B hi]])
    end

    it "treats a trailing # comment on a note's text as running to line end, ; included" do
      diagram = parser.parse("sequenceDiagram\nNote over A: hi # c; B->>C: yo\n")

      expect(diagram.notes.map(&:text)).to eq(["hi"])
      expect(diagram.messages).to be_empty
    end

    it "keeps a literal %% inside message and note text, not stripped as a comment opener" do
      # `text_run` (unlike the older `message_text`/`note_text` this
      # replaced) has no special case for `%%` — only `content_boundary`'s
      # own `#` handling stops a capture early. Guards `message_text`/
      # `note_text` switching to `text_run`: reverting either to the old
      # `(line_end.absent? >> any).repeat` still strips trailing `%% c` via
      # a builder-side rule this diff doesn't touch, so this alone can't
      # separate HEAD from origin/main — it pins the now-correct behavior
      # (mermaid 11.16.1 gives "hi %% c" for both).
      diagram = parser.parse("sequenceDiagram\nA->>B: hi %% c\n")
      notes = parser.parse("sequenceDiagram\nNote over A: hi %% c\n")

      expect(diagram.messages.last.message_text).to eq("hi %% c")
      expect(notes.notes.last.text).to eq("hi %% c")
    end

    it "rejects a lone \\r in the middle of message text" do
      # Guards `text_run`'s fast path excluding `\r`: mermaid 11.16.1
      # rejects this the same way (its own `\r\n?` normalisation never
      # produces a bare mid-text `\r` for its lexer to accept). A mutant
      # that widens `match['^;\n\r#']` to `match['^;\n#']` turns this
      # green — verified via mutation-check.sh.
      source = "sequenceDiagram\nA->>B: a\rb\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "accepts a message whose text ends in a bare \\r with no following newline, at EOF" do
      # `content_boundary`'s `(str("\r") >> eof)` alternative is what makes
      # `text_run` stopping at every `\r` correct rather than a dead end at
      # true EOF — dropping it turns this red (verified via a targeted
      # mutation, not a whole-file revert: origin/main's older, looser
      # `message_text` rule swallows the trailing `\r` into the capture and
      # its own `extract_text` strips it back off, landing on the same "a"
      # by a different, more accidental route, so this spec alone can't
      # separate HEAD from origin/main). mermaid 11.16.1 normalises
      # `\r\n?` to `\n` before parsing, so it accepts source ending in a
      # bare `\r` (`A->>B: a\r` gives message "a").
      diagram = parser.parse("sequenceDiagram\nA->>B: a\r")

      expect(diagram.messages.last.message_text).to eq("a")
    end

    it "accepts a note whose text ends in a bare \\r with no following newline, at EOF" do
      # Same guard as above, applied to `note_statement`.
      diagram = parser.parse("sequenceDiagram\nNote over A: a\r")

      expect(diagram.notes.last.text).to eq("a")
    end

    it "treats a trailing # comment on an alt's opening label as running to line end, ; included" do
      # Guards `content_boundary` consuming `trailing_comment` before
      # checking for `;`/line end: reverting content_boundary to its
      # pre-comment-aware body (`line_end | semicolon`, the actual bug this
      # fixes) turns this red. It can't tell HEAD apart from origin/main,
      # though — origin/main's `alt_label` never splits at `;` at all, so
      # it swallows the whole line (fake message included) and lands on
      # the same single real message by a different, cruder route.
      diagram = parser.parse("sequenceDiagram\nalt x # c; B->>C: yo\nA->>B: m\nend\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[A B]])
    end

    it "treats a trailing # comment on a par's opening label as running to line end, ; included" do
      # Same guard as above, applied to `par`.
      diagram = parser.parse("sequenceDiagram\npar x # c; B->>C: yo\nA->>B: m\nend\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[A B]])
    end

    it "splits an alt's opening label at an inline semicolon, matching case 053" do
      source = "sequenceDiagram\nalt;A->>B: m\nend\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map(&:message_text)).to eq(["m"])
    end

    it "splits a par's opening label at an inline semicolon, matching case 054" do
      source = "sequenceDiagram\npar;A->>B: m\nend\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map(&:message_text)).to eq(["m"])
    end

    it "parses a bare hash-comment line left over after a label's semicolon split" do
      # Guards `hash_comment_statement`, which doesn't exist on origin/main
      # at all: deleting the rule turns this red. It can't tell HEAD apart
      # from origin/main, though — origin/main's `alt_label` never splits
      # at `;`, so the whole line becomes the label and the leftover-
      # comment-line case this rule exists for never arises there.
      source = "sequenceDiagram\nalt -:<>,;# comment\nA->>B: m\nend\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map(&:message_text)).to eq(["m"])
    end

    it "parses an alt/else with a hash-heavy else label, matching case 049" do
      # `#` precedes `;` in this label, so `trailing_comment` swallows both
      # either way — this alone can't prove `else_label` is `;`-aware; see
      # "splits else_label at an inline semicolon" below for that. This
      # case only pins that a punctuation-heavy else label parses at all.
      source = "sequenceDiagram\nalt -:<>,;# comment\nA->>B: m\n" \
                "else ,<>:-#; comment\nA->>B: m\nend\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map(&:message_text)).to eq(%w[m m])
    end

    it "reads a message whose sender opens with a character reference, not as a comment line" do
      diagram = parser.parse("sequenceDiagram\n#9829;B->>C: m\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([["#9829;B", "C"]])
    end
  end

  # Covers every `rule(:statement)` alternative except `comment_statement`/
  # `hash_comment_statement` (swallow to line end regardless of `;`, no
  # message to survive) and the block/control-structure statements (see
  # "#parse inline semicolons in block-opening and continuation labels"
  # instead). Check `rule(:statement)` before adding a new statement kind.
  describe "#parse inline semicolons across every dispatched statement kind" do
    it "keeps title_statement's own text and the message that follows a semicolon" do
      diagram = parser.parse("sequenceDiagram\ntitle T;A->>B: m\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    # Unlike every other row here, `accTitle`/`accDescr` do NOT split at an
    # inline `;` on REAL mermaid either — measured against mermaid 11.16.1:
    # `accTitle: T;A->>B: m` gives 0 messages, the whole `T;A->>B: m`
    # swallowed into the (unrendered) title text. Sirena's `rest_of_line`-
    # based `acc_title_statement`/`acc_descr_statement` already match that
    # and are untouched by this diff — nothing here needed fixing.
    it "swallows an inline semicolon into acc_title_statement's text, matching mermaid" do
      diagram = parser.parse("sequenceDiagram\naccTitle: T;A->>B: m\n")

      expect(diagram.messages).to be_empty
    end

    it "swallows an inline semicolon into acc_descr_statement's text, matching mermaid" do
      diagram = parser.parse("sequenceDiagram\naccDescr: T;A->>B: m\n")

      expect(diagram.messages).to be_empty
    end

    it "keeps acc_descr_block's own text and the message that follows a semicolon" do
      diagram = parser.parse("sequenceDiagram\naccDescr {T};A->>B: m\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    it "keeps autonumber_statement's own effect and the message that follows a semicolon" do
      diagram = parser.parse("sequenceDiagram\nautonumber;A->>B: m\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    it "labels a create_statement's alias and keeps the message that follows a semicolon" do
      diagram = parser.parse("sequenceDiagram\ncreate participant B as Bee;A->>B: m\n")

      expect(diagram.find_participant("B").label).to eq("Bee")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    it "resolves a destroy_statement's target and keeps the message that follows a semicolon" do
      diagram = parser.parse("sequenceDiagram\nparticipant B\ndestroy B;A->>B: m\n")

      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    it "declares a links_statement's target and keeps the message that follows a semicolon" do
      diagram = parser.parse("sequenceDiagram\nlinks A: {};A->>B: m\n")

      expect(diagram.participants.map(&:id)).to eq(%w[A B])
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    it "declares two participant_declarations and keeps the message after the second semicolon" do
      diagram = parser.parse("sequenceDiagram\nparticipant A;participant B;A->>B: m\n")

      expect(diagram.participants.map(&:id)).to eq(%w[A B])
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    it "declares an actor_declaration and keeps the message that follows a semicolon" do
      diagram = parser.parse("sequenceDiagram\nactor B;A->>B: m\n")

      expect(diagram.find_participant("B").actor_type).to eq("actor")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    it "keeps a note_statement's own text and the message that follows a semicolon" do
      diagram = parser.parse(
        "sequenceDiagram\nparticipant A\nparticipant B\nNote over A: n;A->>B: m\n",
      )

      expect(diagram.notes.map(&:text)).to eq(["n"])
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B m]])
    end

    # `activate`/`deactivate` share this exact shape (measured against
    # mermaid 11.16.1: `activate A;A->>B: m` keeps both), but their
    # `line_end` terminator is untouched by this diff (`git diff
    # f532168e HEAD` — identical to origin/main) — pre-existing, same
    # status as singular `link`, out of scope here.
    it "documents activation_command's inline semicolon as a known, pre-existing gap" do
      source = "sequenceDiagram\nparticipant A\nactivate A;A->>B: m\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "documents deactivation_command's inline semicolon as a known, pre-existing gap" do
      source = "sequenceDiagram\nparticipant A\nactivate A\ndeactivate A;A->>B: m\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end
  end

  # Each row parses through the raw grammar (not the full `parser`) to pin
  # the label text itself, alongside the message that follows the `;`
  # through the full parser — checking only one of the two would miss a
  # regression that either swallows "lost" into the label or drops the
  # message. `rect` is excluded: it has no rule in this grammar at all.
  describe "#parse inline semicolons in block-opening and continuation labels" do
    it "splits box_label at an inline semicolon" do
      source = "sequenceDiagram\nbox B;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:box_label].to_s).to eq("B")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B lost]])
    end

    it "splits loop_label at an inline semicolon" do
      source = "sequenceDiagram\nloop L;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:loop_label].to_s).to eq("L")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B lost]])
    end

    it "splits alt_label at an inline semicolon" do
      source = "sequenceDiagram\nalt X;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:alt_label].to_s).to eq("X")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B lost]])
    end

    it "splits else_label at an inline semicolon" do
      source = "sequenceDiagram\nalt X\nC->>D: k1\nelse Y;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:else_blocks].first[:else_label].to_s).to eq("Y")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[C D k1], %w[A B lost]])
    end

    it "splits opt_label at an inline semicolon" do
      source = "sequenceDiagram\nopt O;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:opt_label].to_s).to eq("O")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B lost]])
    end

    it "splits par_label at an inline semicolon" do
      source = "sequenceDiagram\npar X;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:par_label].to_s).to eq("X")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B lost]])
    end

    it "splits and_label at an inline semicolon" do
      source = "sequenceDiagram\npar X\nC->>D: k1\nand Y;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:and_blocks].first[:and_label].to_s).to eq("Y")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[C D k1], %w[A B lost]])
    end

    it "splits critical_label at an inline semicolon" do
      source = "sequenceDiagram\ncritical X;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:critical_label].to_s).to eq("X")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B lost]])
    end

    it "splits option_label at an inline semicolon (H1)" do
      source = "sequenceDiagram\ncritical X\nC->>D: k1\noption Y;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:option_blocks].first[:option_label].to_s).to eq("Y")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[C D k1], %w[A B lost]])
    end

    it "splits break_label at an inline semicolon" do
      source = "sequenceDiagram\nbreak Br;A->>B: lost\nend\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)
      diagram = parser.parse(source)

      expect(tree[1][:break_label].to_s).to eq("Br")
      expect(diagram.messages.map { |m| [m.from_id, m.to_id, m.message_text] })
        .to eq([%w[A B lost]])
    end
  end

  describe "#parse opt vs option" do
    it "rejects opt glued to a word with no space" do
      source = "sequenceDiagram\noptFoo\nA->>B: m\nend\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "accepts opt followed by a real space" do
      # Non-regression companion to "rejects opt glued to a word with no
      # space" above: guards the new `match['a-zA-Z0-9_'].absent?`
      # word-boundary check on `opt_structure` from also rejecting the
      # ordinary case. origin/main accepts `opt Foo` too, with no such
      # check at all, so this alone can't separate HEAD from origin/main.
      # Asserts the nested message itself, not just the absence of an
      # exception: dropping `process_opt` entirely still parses without
      # raising, producing zero messages — verified via mutation-check.sh.
      source = "sequenceDiagram\nopt Foo\nA->>B: m\nend\n"

      expect(parser.parse(source).messages.map(&:message_text)).to eq(["m"])
    end

    it "rejects a bare option statement outside critical" do
      source = "sequenceDiagram\noption Foo\nA->>B: m\nend\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "parses a critical block with two option blocks, matching case 041's shape" do
      source = <<~MERMAID
        sequenceDiagram
        critical Establish a connection to the DB
        Service-->DB: connect
        option Network timeout
        Service-->Service: Log error
        option Credentials rejected
        Service-->Service: Log different error
        end
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.messages.size).to eq(3)
    end
  end

  describe "#parse create/destroy declarations" do
    it "accepts a created participant whose next message targets it" do
      source = "sequenceDiagram\ncreate participant Carl\nA->>Carl: hi\n"

      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to include("Carl")
    end

    it "accepts a created actor with an alias label" do
      source = "sequenceDiagram\ncreate actor D as Donald\nA->>D: hi\n"

      diagram = parser.parse(source)
      donald = diagram.find_participant("D")

      expect([donald.label, donald.actor_type]).to eq(%w[Donald actor])
    end

    it "rejects create with no target" do
      # Keep the space after `participant`: without it the input fails
      # at the keyword and never reaches `declaration_name`. Keep the
      # message match too: with `declaration_name` made optional,
      # `check_lifecycle!` still raises ParseError, so the class alone
      # stays green under that mutant.
      source = "sequenceDiagram\ncreate participant \nA->>B: m\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, /Failed to match sequence/)
    end

    it "rejects create glued to participant with no space" do
      source = "sequenceDiagram\ncreateparticipant Carl\nA->>Carl: m\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "rejects create missing the participant/actor keyword" do
      source = "sequenceDiagram\ncreate Carl\nA->>Carl: m\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "accepts a destroy of an established participant, resolved by a later message" do
      source = "sequenceDiagram\nparticipant Bob\ndestroy Bob\nA->>Bob: m\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[A Bob]])
    end

    it "rejects destroy with no target" do
      # `"destroy\nA->>B: m\n"` fails at `space.repeat(1)` the same way
      # the old `create` case did — same fix, same spec-audit finding,
      # same reason the message match above is load-bearing rather than
      # decoration.
      source = "sequenceDiagram\ndestroy \nA->>B: m\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, /Failed to match sequence/)
    end

    # Each row is `[source, expected participant ids, expected message
    # count]` — `create_statement`/`destroy_statement` end at
    # `content_boundary`, not `line_end`, precisely so a `;`-joined
    # statement on the same line reaches the message right after it.
    # Measured against mermaid 11.16.1: all three give 2 participants,
    # 1 message.
    inline_semicolon = {
      "a create participant followed by its message on the same line" =>
        ["sequenceDiagram\ncreate participant B;A->>B: m\n", %w[B A], 1],
      "a create actor followed by its message on the same line" =>
        ["sequenceDiagram\ncreate actor B;A->>B: m\n", %w[B A], 1],
      "a destroy followed by its message on the same line" =>
        ["sequenceDiagram\ndestroy B;B->>A: m\n", %w[B A], 1],
    }

    inline_semicolon.each do |description, (source, expected_ids, expected_count)|
      it "accepts #{description}" do
        diagram = parser.parse(source)

        expect([diagram.participants.map(&:id), diagram.messages.size])
          .to eq([expected_ids, expected_count])
      end
    end
  end

  describe "#parse character references in declaration and destroy targets" do
    it "accepts a character reference as a create alias id, keeping the alias label" do
      source = "sequenceDiagram\ncreate participant #9829;B as Heart\nA->>#9829;B: hi\n"

      diagram = parser.parse(source)
      heart = diagram.find_participant("#9829;B")

      expect([heart.id, heart.label]).to eq(["#9829;B", "Heart"])
    end

    it "accepts a character reference as a destroy target" do
      source = "sequenceDiagram\ndestroy #9829;B\nA->>#9829;B: m\n"

      tree = Sirena::Parser::Grammars::Sequence.new.parse(source)

      expect(tree[1][:destroy].to_s).to eq("#9829;B")
    end

    it "rejects a bare hash (not a valid character reference) as a destroy target" do
      # No following message: with one present, removing `hash_char.
      # absent?` from `hash_free_lead` still raises ParseError, but via a
      # DIFFERENT path — `#B` no longer matches `content_boundary` right
      # before `A->>B: m`, not the hash-char ban this test names. Dropping
      # the message isolates the ban itself: mermaid 11.16.1 also rejects
      # a bare `destroy #B` on its own ("Lexical error... Unrecognized
      # text").
      source = "sequenceDiagram\ndestroy #B\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "rejects a bare hash in a participant declaration" do
      source = "sequenceDiagram\nparticipant #B\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "rejects a leading bare hash in a participant declaration even with an alias" do
      # Guards the alias branch's own hash-char ban specifically
      # (`declaration_word_lead`, tried only when an `as` keyword
      # follows): the sibling case above only exercises the fallback
      # branch (no `as`). Reverting the alias branch's ban (dropping
      # `hash_char.absent?` from `declaration_word_lead`, keeping the
      # fallback branch's ban untouched) turns this red without touching
      # the sibling case.
      source = "sequenceDiagram\nparticipant #B as Heart\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "consumes a character reference past the first character of a declared id, with no alias" do
      # Guards the `char_ref` alternative in `declaration_name`'s fallback
      # tail (grammar's alias-less branch): dropping it there makes
      # `declaration_char` stop reading at the `;` inside `#9829;`,
      # truncating the id. mermaid 11.16.1 gives the same full id.
      diagram = parser.parse("sequenceDiagram\nparticipant X#9829;Y\n")

      expect(diagram.participants.map(&:id)).to eq(["X#9829;Y"])
    end

    it "consumes a character reference past the first character of a declared id, with an alias" do
      # Guards the `char_ref` alternative in `declaration_name`'s
      # alias-branch tail specifically: dropping only that one (leaving
      # the fallback-branch alternative above untouched) makes the
      # `as`-lookahead fail to see past the `;`, so the whole id+alias
      # falls through to the fallback branch and the alias is lost.
      # mermaid 11.16.1 gives id "X#9829;Y", label "H".
      diagram = parser.parse("sequenceDiagram\nparticipant X#9829;Y as H\n")
      participant = diagram.find_participant("X#9829;Y")

      expect([participant.id, participant.label]).to eq(["X#9829;Y", "H"])
    end

    it "accepts a hash past the first character of a declared id" do
      # Guards `declaration_lead`/`declaration_word_lead` narrowing the ban
      # to the id's first character only: reverting to a whole-id ban (add
      # `hash_char` back to `declaration_stop`) turns this red. It cannot
      # tell HEAD apart from an unrelated origin/main, though — origin/main
      # never banned `#` at all, leading or not, so it accepts `A#B` for a
      # completely different (more permissive) reason.
      source = "sequenceDiagram\nparticipant A#B\nA#B->>C: m\n"

      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to eq(%w[A#B C])
    end

    it "accepts a hash past the first character of a destroy target" do
      # Same guard as above, applied to a `destroy` target's id.
      source = "sequenceDiagram\nparticipant B#C\ndestroy B#C\nA->>B#C: m\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([["A", "B#C"]])
    end
  end

  describe "#parse character references in message actors" do
    it "rejects a bare hash as a message actor" do
      source = "sequenceDiagram\nA->>#B: m\n"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "accepts a character reference as a message actor" do
      diagram = parser.parse("sequenceDiagram\nA->>#9829;: m\n")

      expect(diagram.messages.last.to_id).to eq("#9829;")
    end

    it "consumes a character reference in the middle of a message recipient's name" do
      # Guards the `char_ref` alternative in `message_actor_name`'s
      # repeated tail: dropping it makes the plain character rule stop at
      # the `;` inside `#9829;`, truncating the name. mermaid 11.16.1
      # gives the full "X#9829;Y".
      diagram = parser.parse("sequenceDiagram\nA->>X#9829;Y: m\n")

      expect(diagram.messages.last.to_id).to eq("X#9829;Y")
    end

    it "consumes a character reference at the end of a message sender's name" do
      # Same guard as above, applied to the sender side and to a
      # reference sitting at the very end of the name (no trailing text
      # after the `;`).
      diagram = parser.parse("sequenceDiagram\nX#9829;->>B: m\n")

      expect(diagram.messages.last.from_id).to eq("X#9829;")
    end

    it "accepts a hash past the first character of a message recipient" do
      # Guards `message_actor_lead_char`'s narrowed ban the same way as the
      # declaration pair above: reverting to a whole-name ban (add
      # `hash_char` back to `message_actor_stop`) turns this red, but
      # origin/main's own version never banned `#` at all, so this can't
      # separate HEAD from an unrelated origin/main either.
      diagram = parser.parse("sequenceDiagram\nA->>B#C: m\n")

      expect(diagram.messages.last.to_id).to eq("B#C")
    end

    it "accepts a hash past the first character of a message sender" do
      # Same guard as above, applied to the sender side.
      diagram = parser.parse("sequenceDiagram\nA#x->>B: m\n")

      expect(diagram.messages.last.from_id).to eq("A#x")
    end
  end

  describe "#parse links statements" do
    # Each row is `[source, expected diagram.participants ids]` — the
    # id, not just "didn't raise", is what proves `ensure_participant` got
    # the right target rather than a truncated or wrongly-split one (a
    # wrong target from a bug in `message_actor_name` would stay green
    # against a bare `not_to raise_error`).
    accepted = {
      "unterminated payload, trailing space, EOF (case 055's own shape)" =>
        ["sequenceDiagram\nparticipant a\nlinks a: { ", ["a"]],
      "unterminated payload, no trailing space, EOF" =>
        ["sequenceDiagram\nparticipant a\nlinks a: {", ["a"]],
      "nothing after the colon" =>
        ["sequenceDiagram\nparticipant a\nlinks a:\n", ["a"]],
      "well-formed JSON payload" =>
        ["sequenceDiagram\nparticipant a\nlinks a: {\"Repo\": \"x\"}\n", ["a"]],
      "a character reference as the target" =>
        ["sequenceDiagram\nlinks #9829;B: {}\n", ["#9829;B"]],
      "no space before the colon" =>
        ["sequenceDiagram\nlinks 8:{}\n", ["8"]],
      "a space inside the name, not before the colon" =>
        ["sequenceDiagram\nlinks Alice Smith: {}\n", ["Alice Smith"]],
    }
    # `links` isn't a keyword on origin/main at all, so every row below
    # already raises a generic "failed to parse" `Sirena::Parser::ParseError`
    # there too, with no `links`-specific text a message matcher could key
    # on — same non-discriminating-against-a-whole-file-revert shape as the
    # `create`/`destroy` group above. Each still guards a real HEAD-level
    # constraint of `links_statement` (spot-checked "no colon at all" with a
    # targeted mutation making `colon` optional: turns red).
    rejected = {
      "no colon at all" =>
        "sequenceDiagram\nparticipant a\nlinks a\n",
      "bare, no target" =>
        "sequenceDiagram\nlinks\n",
      "a bare hash as the target" =>
        "sequenceDiagram\nlinks #B: {}\n",
      "parentheses in the target" =>
        "sequenceDiagram\nlinks A()B: {}\n",
      # Documents accept/reject parity with mermaid, not a probe for
      # `links_statement`'s own "no space? before colon" choice: the
      # rejection here comes from `mermaid_token_opener`'s pre-existing
      # number/space lookahead (see the comment above `links_statement`
      # in the grammar) and stays rejected whether or not `space?` sits
      # before `colon` — probed directly, no accept/reject row can
      # distinguish the two, because `message_actor_name`'s repeat never
      # excludes a plain space and so already swallows one before the
      # colon is ever reached.
      "a space before the colon" =>
        "sequenceDiagram\nlinks 8 : {}\n",
      "a leading dash on the target" =>
        "sequenceDiagram\nlinks -A: {}\n",
    }

    accepted.each do |description, (source, expected_ids)|
      it "accepts #{description}" do
        diagram = parser.parse(source)

        expect(diagram.participants.map(&:id)).to eq(expected_ids)
      end
    end

    rejected.each do |description, source|
      it "rejects #{description}" do
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "matches case 056's full shape: a links line after a closed box" do
      source = File.read(
        File.expand_path(
          "../../mermaid/sequence/056_parser_should_handle_box_55.mmd", __dir__
        ),
      )

      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to eq(%w[a b c])
    end

    it "declares its target as a participant, in source order" do
      source = "sequenceDiagram\nlinks B: {}\nparticipant A\nA->>C: m\n"

      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to eq(%w[B A C])
    end
  end

  describe "#parse create/destroy lifecycle" do
    it "rejects a create whose next message has the created id as the source, not the target" do
      source = "sequenceDiagram\ncreate participant Carl\nCarl->>A: m\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, /created participant Carl/)
    end

    it "rejects a create never referenced by the following message" do
      source = "sequenceDiagram\ncreate participant Carl\nA->>B: m\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, /created participant Carl/)
    end

    it "rejects a destroy never referenced by the following message" do
      source = "sequenceDiagram\ndestroy Bob\nA->>C: hi\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, /destroyed participant Bob/)
    end

    it "accepts a destroy resolved by the following message naming it as the target" do
      source = "sequenceDiagram\ndestroy Bob\nA->>Bob: m\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[A Bob]])
    end

    it "accepts a destroy resolved by the following message naming it as the source" do
      source = "sequenceDiagram\ndestroy Bob\nBob->>A: m\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[Bob A]])
    end

    # `register_created`'s duplicate-id check reads `@known_actor_ids`,
    # not `diagram.participants` — every row below introduces the id
    # through a DIFFERENT statement kind (declaration, message, note,
    # `links`) to prove each of `ensure_participant`'s callers actually
    # tracks into that set, not just the declaration path.
    already_known = {
      "a declared participant" =>
        "sequenceDiagram\nparticipant A\ncreate participant A\nX->>A: m\n",
      "an id introduced by an earlier message" =>
        "sequenceDiagram\nX->>A: m\ncreate participant A\nX->>A: m\n",
      "an id introduced by a note" =>
        "sequenceDiagram\nNote over C: x\ncreate participant C\nX->>C: m\n",
      "an id introduced by a links line" =>
        "sequenceDiagram\nlinks C: {}\ncreate participant C\nX->>C: m\n",
    }

    already_known.each do |description, source|
      it "rejects a create whose id already belongs to #{description}" do
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /same id/)
      end
    end

    it "gives create priority over a still-pending destroy on the same message" do
      source = "sequenceDiagram\nparticipant Bob\ndestroy Bob\n" \
                "create participant Carl\nA->>Carl: m\n"

      diagram = parser.parse(source)

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[A Carl]])
    end

    it "resolves a create across a loop boundary" do
      # Asserts the nested message itself, not just the absence of an
      # exception: dropping `process_loop` entirely still parses without
      # raising, producing zero messages — verified via mutation-check.sh.
      source = <<~MERMAID
        sequenceDiagram
        create participant Carl
        loop Retry
        A->>Carl: hi
        end
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[A Carl]])
    end

    it "rejects an unresolved destroy declared outside a loop it spans into" do
      source = <<~MERMAID
        sequenceDiagram
        destroy Bob
        loop Retry
        A->>C: hi
        end
      MERMAID

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, /destroyed participant Bob/)
    end

    it "clears a pending destroy between diagrams on a reused builder" do
      builder = Sirena::Parser::Builders::Sequence.new

      first_tree = Sirena::Parser::Grammars::Sequence.new
        .parse("sequenceDiagram\ndestroy Bob\n")
      builder.apply(first_tree)

      second_tree = Sirena::Parser::Grammars::Sequence.new
        .parse("sequenceDiagram\nA->>B: m\n")
      diagram = builder.apply(second_tree)

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[A B]])
    end

    it "clears a pending create between diagrams on a reused builder" do
      builder = Sirena::Parser::Builders::Sequence.new

      first_tree = Sirena::Parser::Grammars::Sequence.new
        .parse("sequenceDiagram\ncreate participant Carl\n")
      builder.apply(first_tree)

      second_tree = Sirena::Parser::Grammars::Sequence.new
        .parse("sequenceDiagram\nA->>B: m\n")
      diagram = builder.apply(second_tree)

      expect(diagram.messages.map { |m| [m.from_id, m.to_id] }).to eq([%w[A B]])
    end

    it "accepts a create whose id was only referenced by an earlier activate" do
      source = "sequenceDiagram\nactivate C\ncreate participant C\nA->>C: m\n"

      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to include("C")
    end
  end

  describe "#parse the 8 target corpus cases" do
    target_cases = %w[
      019_rendering_sequencediagram_spec_sequence_18
      026_parser_should_handle_semicolons_25
      028_spec_diagram_spec_27
      041_parser_should_handle_critical_statements_with_options_40
      053_parser_should_handle_no-label_alt_52
      054_parser_should_handle_no-label_par_53
      055_parser_should_handle_links_54
      056_parser_should_handle_box_55
    ].freeze

    target_cases.each do |case_name|
      it "parses #{case_name} and renders well-formed SVG" do
        source = File.read(
          File.expand_path("../../mermaid/sequence/#{case_name}.mmd", __dir__),
        )

        svg = Sirena::Engine.new.render(source)

        expect(REXML::Document.new(svg).root&.name).to eq("svg")
      end
    end

    it "case 019 parses every create/destroy declaration into a participant" do
      source = File.read(
        File.expand_path(
          "../../mermaid/sequence/019_rendering_sequencediagram_spec_sequence_18.mmd", __dir__
        ),
      )

      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to eq(%w[Alice Bob Carl D])
    end
  end

  describe "#parse case 018, not one of the 8 targets" do
    it "raises because the destroy target does not match the following message" do
      source = File.read(
        File.expand_path(
          "../../mermaid/sequence/018_rendering_sequencediagram_spec_sequence_17.mmd", __dir__
        ),
      )

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, /destroyed participant Bo does not/)
    end
  end

  describe "#parse regression guard: cases already passing before this diff" do
    # By design these also pass unchanged against origin/main — that's the
    # point of a regression guard, proving this diff didn't break a case
    # that already worked. Not expected to discriminate HEAD from a
    # whole-file revert.
    regression_cases = %w[
      030_spec_diagram_spec_29
      044_parser_it_should_handle_par_over_statements_43
      046_parser_should_handle_special_characters_in_notes_45
      047_parser_should_handle_special_characters_in_loop_46
      048_parser_should_handle_special_characters_in_opt_47
      049_parser_should_handle_special_characters_in_alt_48
      050_parser_should_handle_special_characters_in_par_49
    ].freeze

    regression_cases.each do |case_name|
      it "still parses and renders #{case_name} without raising" do
        source = File.read(
          File.expand_path("../../mermaid/sequence/#{case_name}.mmd", __dir__),
        )

        svg = Sirena::Engine.new.render(source)

        expect(REXML::Document.new(svg).root&.name).to eq("svg")
      end
    end
  end
end
