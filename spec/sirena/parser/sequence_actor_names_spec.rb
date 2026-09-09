# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"
require "rexml/document"

# Bucket B1 (+B2 co-requisite): a Mermaid actor name is a bounded run of
# text, not a programming identifier. These 15 oracle-valid corpus cases
# fail on base because `identifier` rejects spaces, parentheses, dashes,
# `=` and a leading digit in an actor name.
#
# Provenance: §8.1/§8.2 and §8.5's 017 expectations are the oracle's own
# actor list, read off the pinned reference SVG. §8.3, the first two rows
# of §8.5, and §8.6 are hand-written minimal documents with no corpus case
# behind them; §8.3 and §8.6 preserve base behaviour, the first two rows
# of §8.5 are new behaviour that raises on base.
RSpec.describe Sirena::Parser::SequenceParser do
  let(:parser) { described_class.new }

  def ids_for(path)
    parser.parse(File.read(path)).participants.map(&:id)
  end

  describe "the actor-name token — four sub-shapes" do
    it "keeps a dash inside an actor name distinct from the arrow" do
      ids = ids_for(
        "spec/mermaid/sequence/012_parser_should_handle_dashes_in_actor_names_11.mmd"
      )

      expect(ids).to eq(%w[Alice-in-Wonderland Bob])
    end

    it "keeps an = inside a participant name distinct from an assignment" do
      ids = ids_for(
        "spec/mermaid/sequence/014_parser_should_handle_equals_in_participant_names_13.mmd"
      )

      expect(ids).to eq(%w[Alice=Wonderland Bob])
    end

    it "accepts a leading-digit actor name" do
      ids = ids_for(
        "spec/mermaid/sequence/031_parser_should_handle_notes_and_messages_without_wrap_specified_30.mmd"
      )

      expect(ids).to eq(%w[1 2 3 4])
    end

    # `()` touching a message endpoint is mermaid's own central-connection
    # decoration, not actor-name material — measured against mermaid
    # 11.16.1 directly and against its jison grammar (the `()` terminal
    # feeding `LINETYPE.CENTRAL_CONNECTION`/`_REVERSE`/`_DUAL`). The oracle
    # SVG (spec/fixtures_mermaid/sequence/010_..._9.svg) draws extra boxes
    # labelled e.g. "Alice ()", but those are connection-point markers on
    # the rendered lifeline, not actors: mermaid's own `db.getActors()` on
    # this source returns exactly the three declared actors, whether the
    # decoration sits on one endpoint (`Bob ()-->> Charlie`) or both
    # (`Alice ()->>() Bob`).
    it "discards () as a central-connection decoration, not actor-name material" do
      ids = ids_for(
        "spec/mermaid/sequence/010_rendering_sequencediagram-v2_spec_sequence_9.mmd"
      )

      expect(ids).to eq(%w[Alice Bob Charlie])
    end
  end

  describe "implicit creation, ordering and dedup" do
    # 014 differs from the case above by mixing decorated and undecorated
    # messages between the same three actors (`Alice ->> Bob` plain, then
    # `Bob ()->>() Charlie` dual-decorated, then `Charlie -->> Alice`
    # plain again) — coverage the always-decorated 010 case above cannot
    # give. Measured against mermaid directly: `db.getActors()` on this
    # source returns exactly the three declared actors.
    it "does not turn a central-connection decoration into an implicit actor" do
      ids = ids_for(
        "spec/mermaid/sequence/014_rendering_sequencediagram-v2_spec_sequence_13.mmd"
      )

      expect(ids).to eq(%w[Alice Bob Charlie])
    end

    # Fixture 014's three declarations all precede every message, so it
    # cannot tell single-pass, document-order processing apart from an
    # implementation that batches every declaration before any message —
    # both give the same array. This inline source interleaves a
    # `participant` declaration BETWEEN two messages, after an implicit
    # actor has already appeared, which only the correct ordering passes.
    it "keeps a declaration in its textual position relative to implicit actors" do
      source = "sequenceDiagram\nA->>B: m\nparticipant C\nB->>C: m2\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[A B C])
    end
  end

  describe "the whitespace hazard — one example per reachable capture site" do
    # Each source below is written as an explicit literal with the
    # trailing space named, because the natural spelling (no trailing
    # space) already yields a clean id on base and would pass with the
    # normalisation reverted — making the example vacuous.
    it "strips a trailing space after a participant declaration" do
      source = "sequenceDiagram\nparticipant A \nA->>B: m\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[A B])
    end

    it "strips a leading space before the colon in a message" do
      source = "sequenceDiagram\nparticipant B\n    A->>B : m\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[B A])
    end

    it "strips a leading space before the comma in a note participant list" do
      source = "sequenceDiagram\nA->>B: m\nNote over A , B: n\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[A B])
    end

    # Asserting only "does not raise" would stay green for a fix that
    # silently dropped the activation record instead of normalising the
    # id — `track_activation` becoming a no-op passes that assertion too.
    # The activation record itself is what proves the trailing space was
    # stripped rather than swallowed.
    it "strips a trailing space at the activate/deactivate site" do
      source = "sequenceDiagram\nA->>B: m\nactivate B \nB->>A: r\ndeactivate B\n"
      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to eq(%w[A B])
      expect(diagram.activations.map { |a| [a.participant_id, a.start_index, a.end_index] })
        .to eq([["B", 1, 2]])
    end
  end

  describe "regression pins — green on base and unchanged on head" do
    it "still splits on a semicolon statement separator" do
      source = "sequenceDiagram\nparticipant A;\nA->>B: m\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[A B])
    end

    it "still recognises the as alias keyword" do
      source = "sequenceDiagram\nparticipant Cast\nCast->>B: m\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[Cast B])
    end

    it "still normalises a trailing space at deactivate" do
      source = "sequenceDiagram\nA->>B: m\nactivate B\ndeactivate B \n"
      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to eq(%w[A B])
      expect(diagram.activations.map { |a| [a.participant_id, a.start_index, a.end_index] })
        .to eq([["B", 1, 1]])
    end

    it "still normalises a leading space before the colon in a single-actor note" do
      source = "sequenceDiagram\nA->>B: m\nNote over A : n\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[A B])
    end
  end

  describe "the as alias hazard" do
    it "does not let the alias keyword eat the label" do
      diagram = parser.parse(
        File.read(
          "spec/mermaid/sequence/030_parser_should_handle_different_line_breaks_29.mmd"
        )
      )

      expect(diagram.participants.map(&:id)).to eq(%w[1 2 3 4])
      expect(diagram.participants.map(&:label)).to eq(
        ["multiline<br>text", "multiline<br/>text", "multiline<br />text",
         "multiline<br \\t/>text"]
      )
    end
  end

  describe "sites widened for construct completeness — no corpus case forces these" do
    it "parses a leading-digit actor declaration" do
      source = "sequenceDiagram\nactor 1\n1->>2: m\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[1 2])
    end

    it "parses activate/deactivate on a leading-digit actor" do
      source = "sequenceDiagram\nparticipant 1\nparticipant 2\n" \
               "activate 1\ndeactivate 1\n1->>2: m\n"
      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to eq(%w[1 2])
      expect(diagram.activations.map { |a| [a.participant_id, a.start_index, a.end_index] })
        .to eq([["1", 0, 0]])
    end

    # B2 co-requisite: shape metadata is parsed and discarded. The actor
    # list is the 5 declared participants only — every message in this
    # fixture decorates one or both of its already-declared endpoints
    # with `()`, which the central-connection fix above discards rather
    # than reads as actor-name material. Measured against mermaid
    # directly: `db.getActors()` on this source returns exactly these 5
    # entries, none of the decorated duplicates.
    it "parses and discards @{...} shape metadata" do
      ids = ids_for(
        "spec/mermaid/sequence/017_rendering_sequencediagram-v2_spec_sequence_16.mmd"
      )

      expect(ids).to eq(%w[Alice Bob Charlie David Eve])
    end

    # shape_metadata bounds its payload to one line. Without that guard
    # an unclosed `@{` scans past the newline into a LATER statement's
    # closing brace and silently discards everything between — measured:
    # actors ["A","E"], messages ["kept"], with the "lost" statement gone
    # and no error raised. No corpus case has this shape; it is
    # constructed, and the guard trades silent corruption for a raise.
    it "raises rather than silently swallowing statements across an unclosed shape" do
      source = "sequenceDiagram\nparticipant A@{\nB->>C: lost\n" \
               "participant D@{\"type\":\"boundary\"}\nA->>E: kept\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "the trailing-comment contract" do
    # Only these two can catch a regression here — the sweep predicate is
    # well-formed SVG, and no sequence corpus case puts a comment on a
    # declaration or an activate/deactivate line.
    it "yields to a trailing %% comment on a participant declaration" do
      source = "sequenceDiagram\nparticipant Alice %% who\nAlice->>Bob: m\n"

      expect(parser.parse(source).participants.map(&:id)).to eq(%w[Alice Bob])
    end

    it "yields to a trailing %% comment on an activate line" do
      source = "sequenceDiagram\nA->>B: m\nactivate A %% why\ndeactivate A\n"
      diagram = parser.parse(source)

      expect(diagram.participants.map(&:id)).to eq(%w[A B])
      expect(diagram.activations.map { |a| [a.participant_id, a.start_index, a.end_index] })
        .to eq([["A", 1, 1]])
    end
  end

  describe "the bucket regression net" do
    bucket_cases = %w[
      010_rendering_sequencediagram-v2_spec_sequence_9
      011_rendering_sequencediagram-v2_spec_sequence_10
      012_parser_should_handle_dashes_in_actor_names_11
      012_rendering_sequencediagram-v2_spec_sequence_11
      013_parser_should_handle_dashes_in_participant_names_12
      013_rendering_sequencediagram-v2_spec_sequence_12
      014_parser_should_handle_equals_in_participant_names_13
      014_rendering_sequencediagram-v2_spec_sequence_13
      015_rendering_sequencediagram-v2_spec_sequence_14
      016_rendering_sequencediagram-v2_spec_sequence_15
      017_rendering_sequencediagram-v2_spec_sequence_16
      030_parser_should_handle_different_line_breaks_29
      031_parser_should_handle_notes_and_messages_without_wrap_specified_30
      032_parser_should_handle_notes_and_messages_with_wrap_specified_31
      033_parser_should_handle_notes_and_messages_with_nowrap_or_line_breaks_32
    ].freeze

    # `REXML::Document.new("")` does not raise — it constructs a document
    # with `root == nil`. Asserting only `not_to raise_error` would stay
    # green for an engine that silently returned an empty string, so the
    # root element's name is the property actually being claimed.
    bucket_cases.each do |case_name|
      it "parses #{case_name} and renders well-formed SVG" do
        source = File.read("spec/mermaid/sequence/#{case_name}.mmd")

        svg = Sirena::Engine.new.render(source)

        expect(REXML::Document.new(svg).root&.name).to eq("svg")
      end
    end

    # Oracle-independent bonus: verdict `unknown`, no reference SVG, so
    # only "parses and renders" is pinned — no spec asserts its actor
    # name (see the plan's declared residual on this case).
    it "parses the unspecced bonus case 020 and renders well-formed SVG" do
      source = File.read(
        "spec/mermaid/sequence/020_rendering_sequencediagram_spec_sequence_19.mmd"
      )

      svg = Sirena::Engine.new.render(source)

      expect(REXML::Document.new(svg).root&.name).to eq("svg")
    end
  end

  describe "characters mermaid never accepts in a message actor name" do
    # `+` is banned only in a MESSAGE endpoint, where it would collide
    # with the activation suffix (`A->>+B`) — a declaration has no arrow
    # to collide with, and mermaid accepts `participant A+B` outright
    # (see "declarations accept what messages must reject" below).
    # `<` is banned in both: measured against mermaid 11.16.1's own
    # parser directly, `A<Z->>B: m` and `participant A<B` both raise.
    ["A->>++B: m", "A->>B+C: m", "A<Z->>B: m"].each do |source|
      it "rejects #{source.inspect}, matching mmdc" do
        expect { parser.parse("sequenceDiagram\n#{source}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    # `/` stays valid actor-name material generally (mermaid accepts
    # `participant A/B`); it is only excluded as the character that OPENS
    # a name, because it also opens three reversed-arrow spellings
    # (`/|-`, `/|--`, `//-`, `//--`). Same shape as the existing `)|>`
    # exclusion: an arrow-tail character cannot open a name.
    it "rejects a message operand opening with /, matching mmdc" do
      expect { parser.parse("sequenceDiagram\nA->>/B: m\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "still accepts a single + as an activation suffix" do
      diagram = parser.parse("sequenceDiagram\nA->>+B: m\n")

      expect(diagram.participants.map(&:id)).to eq(%w[A B])
    end

    # A trailing dash at end-of-statement is exactly as legal as one at
    # end-of-file — mmdc accepts `participant A-` followed by more
    # statements. Measured against mermaid 11.16.1's own parser directly.
    it "accepts a trailing dash in a declaration followed by more statements" do
      diagram = parser.parse("sequenceDiagram\nparticipant A-\nA- ->>B: m\n")

      expect(diagram.participants.map(&:id)).to eq(%w[A- B])
    end

    # A declaration has no arrow next to it, so `+`, a leading `/`, and a
    # `--` run are all ordinary name material — measured against mermaid
    # 11.16.1's own parser directly: `participant A+B`, `participant /B`
    # and `participant A-` (this file's own `actor_char` would reject
    # every one of these in a message).
    it "declarations accept what messages must reject" do
      diagram = parser.parse(
        "sequenceDiagram\nparticipant A+B\nparticipant /B\nparticipant A-\n"
      )

      expect(diagram.participants.map(&:id)).to eq(["A+B", "/B", "A-"])
    end

    # ` as ` only splits id from label inside a `participant`/`actor`
    # statement. A message has no such split: measured against mermaid
    # 11.16.1 directly, `A as Z->>B as Y: m` parses with `as` as ordinary
    # text on both endpoints, not as the alias keyword.
    it "does not treat ' as ' as the alias keyword inside a message" do
      diagram = parser.parse("sequenceDiagram\nA as Z->>B as Y: m\n")

      expect(diagram.participants.map(&:id)).to eq(["A as Z", "B as Y"])
      expect(diagram.messages.map { |m| [m.from_id, m.to_id] })
        .to eq([["A as Z", "B as Y"]])
    end

    # mermaid rejects an empty `@{}` payload; parse-and-ignore must not
    # treat zero characters between the braces as valid metadata.
    it "rejects an empty @{} shape-metadata payload, matching mmdc" do
      expect { parser.parse("sequenceDiagram\nparticipant A@{}\nA->>B: m\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "an empty note renders, it does not crash the pipeline" do
    # extract_text now correctly returns "" for `Note over A:` with no
    # trailing content (mermaid accepts this). Base's own bug returned
    # the literal string "[]", which is non-empty, so this validation
    # path was never reachable on base — a diagram model rule that has
    # always been wrong about mermaid, exposed by this diff's own fix.
    it "renders through the full engine rather than raising Invalid diagram" do
      svg = Sirena::Engine.new.render("sequenceDiagram\nA->>B: m\nNote over A:\n")

      expect(REXML::Document.new(svg).root&.name).to eq("svg")
    end
  end

  describe "extract_text — the nested empty-repeat capture" do
    it "renders an empty trailing message as an empty string, not the literal []" do
      diagram = parser.parse(
        File.read(
          "spec/mermaid/sequence/070_parser_should_parse_a_message_with_a_trailing_colon_but_no_content_69.mmd"
        )
      )

      # `first`, not `last` — case 070 has two messages and the empty one
      # is FIRST. `last` would be "Got it!" and this assertion would be
      # red on a CORRECT implementation.
      expect(diagram.messages.first.message_text).to eq("")
      expect(diagram.messages.last.message_text).to eq("Got it!")
    end

    it "does not leak the literal [] into the rendered SVG" do
      source = File.read(
        "spec/mermaid/sequence/070_parser_should_parse_a_message_with_a_trailing_colon_but_no_content_69.mmd"
      )

      svg = Sirena::Engine.new.render(source)

      expect(svg).not_to include("[]")
    end

    # Also new behaviour: on base this renders the literal "[]", because
    # a note's empty capture reaches `extract_text` directly as `[]`
    # rather than nested in a Hash, and base has no Array branch at all.
    it "renders an empty single-note text as an empty string, not []" do
      source = "sequenceDiagram\nA->>B: m\nNote over A:\n"

      expect(parser.parse(source).notes.map(&:text)).to eq([""])
    end
  end
end
