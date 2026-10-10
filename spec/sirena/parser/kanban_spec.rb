# frozen_string_literal: true

require "spec_helper"
require "timeout"

module KanbanSpecHelpers
  # mermaid gates each field on JS truthiness after js-yaml resolves the
  # scalar, so these are never set and the field falls back. Every value
  # below was driven through mmdc 11.12.0, not recalled.
  def title_for(value)
    parser.parse("kanban\n  id1[A]@{ label: #{value} }\n").columns.first.title
  end

  # A `@{ }` body that gives `key` the value. A value starting with a
  # newline is block-style YAML and gets the body on separate lines.
  def metadata_body(key, value)
    return " #{key}: #{value} " unless value.start_with?("\n")

    "\n      #{key}:#{value}\n    "
  end

  def card_of(key, value)
    body = metadata_body(key, value)
    parsed_card("kanban\n  col[Todo]\n    task1[Task]@{#{body}}\n")
  end

  def parsed_card(source)
    parser.parse(source).columns.first.cards.first
  end

  def expect_single_root_column(diagram, corpus_id)
    aggregate_failures do
      expect(diagram.columns.size).to eq(1), "corpus #{corpus_id}"
      expect(diagram.columns.first.title).to eq("root"), "corpus #{corpus_id}"
    end
  end

  def nested_quoted_parens_source
    <<~MERMAID
      kanban
        col("Todo (urgent)")
          ("Fix (today)")
    MERMAID
  end

  def class_then_icon_source
    <<~MERMAID
      kanban
          root[The root]
          :::m-4 p-8
          ::icon(fa-rocket)
    MERMAID
  end

  def icon_then_class_source
    <<~MERMAID
      kanban
          root[The root]
          ::icon(fa-flag)
          :::m-4 p-8
    MERMAID
  end

  def separated_zeroes
    %w[0_0 0__0 0___0 0_0_0 00__00 -0_0 0x_0 0x0_0 0b0_0 0o0_0]
  end

  def icon_greedy_run = Sirena::Parser::Atoms::GreedyRun.new("[^)]")

  def label_greedy_run = Sirena::Parser::Atoms::GreedyRun.new('[^\]]')

  def empty_match_error = /Expected at least one matching character/

  def column_of(key, value)
    body = metadata_body(key, value)
    source = "kanban\n  col[Todo]@{#{body}}\n    task1[Task]\n"
    parser.parse(source).columns.first
  end

  # `levels` aliased lists of nine, each holding nine of the one before:
  # 9**levels items from about 70 bytes per level. The lists sit under
  # unread keys; only `assigned` joins the last of them.
  def alias_expansion_source(levels, assigned: true)
    entries = ["l0: &l0 [x, x, x, x, x, x, x, x, x]"]
    (1...levels).each do |level|
      nine = (["*l#{level - 1}"] * 9).join(", ")
      entries << "l#{level}: &l#{level} [#{nine}]"
    end
    entries << "assigned: *l#{levels - 1}" if assigned
    "kanban\n  col[Todo]\n    task1[Task]@{ #{entries.join(', ')} }\n"
  end

  # `depth` aliased lists, each holding only the one before, so `assigned`
  # is a list nested `depth` deep from a body that is `depth` entries long.
  def alias_chain_source(depth)
    entries = ["l0: &l0 [x]"]
    (1...depth).each do |level|
      entries << "l#{level}: &l#{level} [*l#{level - 1}]"
    end
    entries << "assigned: *l#{depth - 1}"
    "kanban\n  col[Todo]\n    task1[Task]@{ #{entries.join(', ')} }\n"
  end

  def boards_of(source)
    parser.parse(source).columns.map do |column|
      [column.id, column.cards.map(&:id)]
    end
  end

  # Time to parse the family at four times `size`, over the time at `size`.
  # Each is the fastest of three runs after a warm-up, and the divisor is
  # never below 20ms (see the "with an input that grows" context).
  def growth_ratio(size, build)
    parser.parse(build.call(size / 10))
    small = fastest_parse(build.call(size))
    large = fastest_parse(build.call(size * 4))
    large / [small, 0.02].max
  end

  def fastest_parse(source)
    Array.new(3) { wall_time { parser.parse(source) } }.min
  end

  # One failure per character, named, so a single run lists every one.
  def expect_boards(chars, source_for, cards)
    aggregate_failures do
      chars.each do |name, char|
        expect(boards_of(source_for.call(char)))
          .to eq([["root", cards]]), "with #{name}"
      end
    end
  end

  def expect_refused(chars, source_for)
    aggregate_failures do
      chars.each do |name, char|
        expect { parser.parse(source_for.call(char)) }
          .to raise_error(Sirena::Parser::ParseError), "with #{name}"
      end
    end
  end
end

# Each cell was driven through mmdc 11.12.0 (mermaid 11.12.0, headless
# Chrome); a placement lists the characters mermaid refuses there.
module KanbanLineEndCases
  WHITESPACE = {
    "space" => " ",
    "tab" => "\t",
    "vertical tab" => "\v",
    "form feed" => "\f",
    "no-break space" => "\u00a0",
    "ogham space" => "\u1680",
    "en quad" => "\u2000",
    "hair space" => "\u200a",
    "line separator" => "\u2028",
    "paragraph separator" => "\u2029",
    "narrow no-break space" => "\u202f",
    "medium math space" => "\u205f",
    "ideographic space" => "\u3000",
    "byte order mark" => "\ufeff",
    "carriage return" => "\r",
  }.freeze

  # Not JavaScript whitespace: mermaid refuses each of these wherever
  # whitespace may end an item line (measured against mmdc 11.12.0).
  NOT_WHITESPACE = {
    "zero-width space" => "\u200b",
    "next line" => "\u0085",
    "mongolian vowel separator" => "\u180e",
  }.freeze

  # Placements where one of those characters is ordinary text and mermaid
  # accepts it (a class name, a comment body), or where Sirena still refuses
  # what mermaid accepts (`::icon()` followed by one).
  TEXT_PLACEMENTS = ["after a class modifier", "after an empty class modifier",
                     "before a comment on a class modifier",
                     "before a comment on an empty class modifier",
                     "after a trailing comment",
                     "after an empty icon modifier"].freeze

  SEPARATORS = ["line separator", "paragraph separator"].freeze
  BLANKS_AFTER = ["", "\n", "\n\n", " \n%% c\n", "%% y", "%% y\n",
                  " %% y\n%% z\n"].freeze
  EVERY_SPACE = (WHITESPACE.keys - SEPARATORS - ["carriage return"]).freeze

  # placement => [source with <c> for the character, cards, characters
  # refused]
  PLACEMENTS = {
    "after a closed label" => ["kanban\n  root[Root]<c>\n    a[A]\n", %w[a],
                               []],
    "after a closed label at the end of the input" => [
      "kanban\n  root[Root]<c>", [], []
    ],
    "after item metadata" => [
      "kanban\n  root[Root]@{ ticket: T }<c>\n    a[A]\n", %w[a], []
    ],
    "after a bare id with metadata" => [
      "kanban\n  root@{ ticket: T }<c>\n    a[A]\n", %w[a], []
    ],
    "after an icon modifier" => [
      "kanban\n  root[Root]\n    ::icon(x)<c>\n    a[A]\n", %w[a], []
    ],
    "after a class modifier" => [
      "kanban\n  root[Root]\n    :::hot<c>\n    a[A]\n", %w[a], []
    ],
    "before a comment on a labelled item" => [
      "kanban\n  root[Root]<c>%% x\n    a[A]\n", %w[a], SEPARATORS
    ],
    "before a comment on a round item" => [
      "kanban\n  root(Root)<c>%% x\n    a[A]\n", %w[a], SEPARATORS
    ],
    "before a comment after metadata" => [
      "kanban\n  root[Root]@{ ticket: T }<c>%% x\n    a[A]\n", %w[a], SEPARATORS
    ],
    "before a comment after a bare id with metadata" => [
      "kanban\n  root@{ ticket: T }<c>%% x\n    a[A]\n", %w[a], SEPARATORS
    ],
    "before a comment on an icon modifier" => [
      "kanban\n  root[Root]\n    ::icon(x)<c>%% x\n    a[A]\n",
      %w[a], SEPARATORS
    ],
    "before a comment on a class modifier" => [
      "kanban\n  root[Root]\n    :::hot<c>%% x\n    a[A]\n", %w[a], SEPARATORS
    ],
    "after an empty icon modifier" => [
      "kanban\n  root[Root]\n    ::icon()<c>\n    a[A]\n", %w[a], []
    ],
    "before a comment on an empty icon modifier" => [
      "kanban\n  root[Root]\n    ::icon()<c>%% x\n    a[A]\n", %w[a], SEPARATORS
    ],
    "after an empty class modifier" => [
      "kanban\n  root[Root]\n    a[A]\n    :::<c>\n", %w[a], SEPARATORS
    ],
    "before a comment on an empty class modifier" => [
      "kanban\n  root[Root]\n    a[A]\n    :::<c>%% x\n", %w[a], SEPARATORS
    ],
    "before a comment on its own line" => [
      "kanban\n  root[Root]\n<c>%% x\n    a[A]\n", %w[a], []
    ],
    "after a trailing comment" => ["kanban\n  root[Root]%% x<c>\n    a[A]\n",
                                   %w[a], SEPARATORS],
  }.freeze
end

RSpec.describe Sirena::Parser::Kanban do
  include KanbanSpecHelpers

  let(:parser) { described_class.new }

  describe "#parse" do
    context "with a simple kanban board" do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              docs[Create Documentation]
        MERMAID
      end

      it "parses successfully" do
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Kanban)
      end

      it "creates the correct column", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(1)
        expect(diagram.columns.first.id).to eq("id1")
        expect(diagram.columns.first.title).to eq("Todo")
      end

      it "creates the correct card", :aggregate_failures do
        diagram = parser.parse(source)
        column = diagram.columns.first
        expect(column.cards.size).to eq(1)
        expect(column.cards.first.id).to eq("docs")
        expect(column.cards.first.text).to eq("Create Documentation")
      end
    end

    context "with multiple columns and cards" do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              docs[Create Documentation]
              blog[Create Blog]
            id2[In Progress]
              feature[Implement Feature]
            id3[Done]
              release[Release v1.0]
        MERMAID
      end

      it "creates all columns", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(3)
        expect(diagram.columns.map(&:title))
          .to eq(["Todo", "In Progress", "Done"])
      end

      it "creates all cards in correct columns", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns[0].cards.size).to eq(2)
        expect(diagram.columns[1].cards.size).to eq(1)
        expect(diagram.columns[2].cards.size).to eq(1)
      end
    end

    context "with card metadata" do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              docs[Create Documentation]@{ priority: 'High', ticket: 'MC-1001' }
        MERMAID
      end

      it "parses metadata correctly", :aggregate_failures do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.priority).to eq("High")
        expect(card.ticket).to eq("MC-1001")
      end
    end

    context "with assigned metadata" do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              feature[Implement Feature]@{ assigned: 'dev1' }
        MERMAID
      end

      it "parses assigned field" do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.assigned).to eq("dev1")
      end
    end

    context "with icon metadata" do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              task[Fix bugs]@{ icon: 'star' }
        MERMAID
      end

      it "parses icon field" do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.icon).to eq("star")
      end
    end

    context "with label metadata" do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              task[Task]@{ label: 'urgent' }
        MERMAID
      end

      it "parses label field" do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.label).to eq("urgent")
      end
    end

    context "with multiple metadata fields" do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
              task[Task]@{ priority: 'High', assigned: 'dev1', ticket: 'MC-100' }
        MERMAID
      end

      it "parses all metadata fields", :aggregate_failures do
        diagram = parser.parse(source)
        card = diagram.columns.first.cards.first
        expect(card.priority).to eq("High")
        expect(card.assigned).to eq("dev1")
        expect(card.ticket).to eq("MC-100")
      end
    end

    context "with empty columns" do
      let(:source) do
        <<~MERMAID
          kanban
            id1[Todo]
            id2[Done]
        MERMAID
      end

      it "creates columns without cards", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(2)
        expect(diagram.columns[0].cards.size).to eq(0)
        expect(diagram.columns[1].cards.size).to eq(0)
      end
    end

    context "with invalid syntax" do
      let(:source) { "invalid kanban syntax" }

      it "raises a parse error" do
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    # --- bucket 1: the node label is optional -------------------------------
    # Every context below is named for the mermaid-js corpus cases it pins,
    # under spec/mermaid/kanban/.

    context "with a bare node (corpus 015, 034)" do
      let(:source) { "kanban\n    root\n" }

      it "creates one column whose title falls back to its id", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(1)
        expect(diagram.columns.first.id).to eq("root")
        expect(diagram.columns.first.title).to eq("root")
      end
    end

    context "with a bare hierarchy (corpus 016)" do
      let(:source) { "kanban\n    root\n      child1\n      child2\n" }

      it "nests bare children as cards titled by their ids", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(["root"])
        cards = diagram.columns.first.cards
        expect(cards.map(&:id)).to eq(%w[child1 child2])
        expect(cards.map(&:text)).to eq(%w[child1 child2])
      end
    end

    context "with metadata on a bare top-level node" do
      # Five corpus cases over four distinct payloads (036 and 037 share
      # one); each becomes a single column titled by its id.
      {
        "035" => "assigned: knsv",
        "036/037" => "icon: star",
        "039" => "icon: star, assigned: knsv",
        "041" => "ticket: MC-1234",
      }.each do |corpus_id, payload|
        it "titles the column by its id (corpus #{corpus_id})" do
          diagram = parser.parse("kanban\n        root@{ #{payload} }\n")

          expect_single_root_column(diagram, corpus_id)
        end
      end
    end

    context "with a label: override on a bare column (corpus 040)" do
      let(:source) do
        "kanban\n        root@{ icon: star, label: 'fix things' }\n"
      end

      it "prefers the label metadata over the id" do
        diagram = parser.parse(source)
        expect(diagram.columns.first.title).to eq("fix things")
      end
    end

    context "with constructs at the bare node boundary" do
      # Two directions on purpose: the accept half dies if the bare
      # alternative is removed, the refuse half dies if it is widened past an
      # identifier. Round shapes are covered below (corpus 017, 022, 023,
      # 031); `::icon`/`:::class` directive lines are covered in the
      # 'with an icon/class directive line' context below, now that they
      # are parsed rather than refused.
      it "accepts a bare identifier" do
        ids = parser.parse("kanban\n  root\n").columns.map(&:id)

        expect(ids).to eq(["root"])
      end

      it "still refuses trailing free text after a bare id" do
        # The reason bare_item stays an identifier: mermaid accepts a bare
        # label with spaces, and widening to match would swallow the
        # unsupported constructs above as literal labels.
        aggregate_failures do
          ["root trailing", "root two more words"].each do |line|
            expect { parser.parse("kanban\n  #{line}\n") }
              .to raise_error(Sirena::Parser::ParseError), line
          end
        end
      end
    end

    context "with a round shape and no id (corpus 017)" do
      let(:source) { "kanban\n    (root)\n" }

      it "auto-assigns an id and titles the column from the shape text", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.size).to eq(1)
        expect(diagram.columns.first.id).to eq("kanban-1")
        expect(diagram.columns.first.title).to eq("root")
      end

      it "assigns the next id deterministically " \
         "for a second unlabelled shape", :aggregate_failures do
        diagram = parser.parse("kanban\n  (Col A)\n  (Col B)\n")
        expect(diagram.columns.map(&:id)).to eq(%w[kanban-1 kanban-2])
        expect(diagram.columns.map(&:title)).to eq(["Col A", "Col B"])
      end
    end

    context "with an id and a round shape on a child (corpus 022, 023)" do
      # 022 indents the root; 023 does not. Indentation of the root line
      # never decides which items become columns - only the FIRST
      # item's indent does - so both parse identically.
      {
        "022" => "kanban\n    root\n      theId(child1)\n",
        "023" => "kanban\nroot\n      theId(child1)\n",
      }.each do |corpus_id, source|
        it "accepts the shaped child (corpus #{corpus_id})" do
          diagram = parser.parse(source)
          aggregate_failures do
            expect(diagram.columns.map(&:id)).to eq(["root"]), corpus_id
            card = diagram.columns.first.cards.first
            expect(card.id).to eq("theId"), corpus_id
            expect(card.text).to eq("child1"), corpus_id
          end
        end
      end
    end

    context "with a quoted label on a round-shaped item" do
      # Not from the corpus - a Codex-constructed input. `shaped_item` and
      # `unlabelled_shaped_item` captured a quoted body as literal
      # characters, quotes included, and ended the shape at the first
      # unquoted `)` - so a label containing one broke the parse entirely.
      # Mirrors mindmap.rb's `square_shape`, the existing precedent for
      # quoted content inside a bracketed shape: the quotes are stripped,
      # and a quoted body may contain the shape's own delimiter.
      it "strips the quotes from an id-prefixed round shape" do
        diagram = parser.parse("kanban\n  col(\"Hello\")\n")
        expect(diagram.columns.first.title).to eq("Hello")
      end

      it "strips the quotes from an unlabelled round shape" do
        diagram = parser.parse("kanban\n  (\"Task\")\n")
        expect(diagram.columns.first.title).to eq("Task")
      end

      it "keeps a paren inside a quoted id-prefixed label" do
        diagram = parser.parse("kanban\n  col(\"Todo (urgent)\")\n")
        expect(diagram.columns.first.title).to eq("Todo (urgent)")
      end

      it "keeps a paren inside a quoted unlabelled label" do
        diagram = parser.parse("kanban\n  (\"Fix (today)\")\n")
        expect(diagram.columns.first.title).to eq("Fix (today)")
      end

      it "parses a column and a child both carrying a quoted label", :aggregate_failures do
        diagram = parser.parse("kanban\n  col(\"Hello\")\n    (\"Task\")\n")
        column = diagram.columns.first
        expect(column.title).to eq("Hello")
        expect(column.cards.first.text).to eq("Task")
      end

      it "parses a paren inside quotes on both the column and its child, " \
         "where the unquoted form failed to parse at all", :aggregate_failures do
        diagram = parser.parse(nested_quoted_parens_source)
        column = diagram.columns.first
        expect(column.title).to eq("Todo (urgent)")
        expect(column.cards.first.text).to eq("Fix (today)")
      end
    end

    context "with a malformed quoted label on a round-shaped item" do
      # Not from the corpus - a Codex-constructed input. When the quoted
      # alternative in `round_text` failed - an empty body, or no closing
      # quote at all - the plain alternative silently accepted the leading
      # `"` as an ordinary character, so `col("")` rendered the literal
      # text `""` instead of failing. Mermaid rejects both inputs
      # (`Expecting 'NODE_DESCR', got 'NODE_DEND'`), so Sirena must too.
      it "refuses an empty quoted body rather than rendering literal quotes" do
        expect { parser.parse("kanban\n  col(\"\")\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "refuses an unterminated quoted body " \
         "rather than keeping the leading quote" do
        expect { parser.parse("kanban\n  col(\"unterminated)\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    context "with a markdown-string body on a round-shaped item" do
      # Not from the corpus - a Codex-constructed input. A quoted body that
      # itself opens and closes with a backtick - `"`text`"` - is mermaid's
      # markdown-string syntax: it strips the backtick pair and renders the
      # content through markdown (measured against mmdc 11.12.0: `col("`Hi
      # **urgent**`")` draws `Hi <strong>urgent</strong>`). Sirena has no
      # markdown renderer anywhere in the codebase, so the former behaviour
      # - matching this as an ordinary quoted body - kept the backticks as
      # literal text and drew `` `Hi **urgent**` `` instead. Refused
      # explicitly now, the same way the malformed bodies above are, rather
      # than silently drawing something mermaid does not.
      it "refuses a backtick-wrapped quoted body on an id-prefixed shape" do
        expect { parser.parse("kanban\n  col(\"`Hello`\")\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "refuses a backtick-wrapped quoted body on an unlabelled shape" do
        expect { parser.parse("kanban\n  (\"`Hello`\")\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "refuses an empty backtick-wrapped body the same way mermaid does" do
        expect { parser.parse("kanban\n  col(\"``\")\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "keeps an ordinary quoted body that merely contains a backtick pair" do
        diagram = parser.parse("kanban\n  col(\"Hello `code` world\")\n")
        expect(diagram.columns.first.title).to eq("Hello `code` world")
      end

      # A body with a single, unmatched backtick - `"`Hello"` with no
      # closing backtick before the quote - is not the markdown-string
      # shape above, so this fix leaves it alone: it stays a literal quoted
      # body, matching the sibling malformed-body pin two contexts up.
      # mmdc 11.12.0 actually lexer-errors on this one too ("Unrecognized
      # text"), a pre-existing gap this High does not cover - it is about
      # the closed backtick pair, not a lone backtick.
      it "keeps a quoted body that opens with a backtick " \
         "but never closes one" do
        diagram = parser.parse("kanban\n  col(\"`Hello\")\n")
        expect(diagram.columns.first.title).to eq("`Hello")
      end
    end

    context "with a markdown-string body on a bracket-labelled item" do
      # mmdc 11.12.0 draws `root["`Hi **urgent**`"]` as
      # `Hi <strong>urgent</strong>`; Sirena has no markdown renderer, so it
      # refuses the form as it does for a round shape.
      ['root["`Hi **urgent**`"]', 'root["`Hello`"]', 'root["``"]',
       "root[\"`Hi`\"]@{ icon: star }"].each do |line|
        it "refuses #{line.inspect}" do
          expect { parser.parse("kanban\n  #{line}\n") }.to raise_error(Sirena::Parser::ParseError)
        end
      end

      # mmdc 11.12.0 drops an empty quoted fragment beside quoted or
      # unquoted text. A quote pair after unquoted text remains literal:
      # the unquoted lexer rule consumes the whole run before the empty
      # fragment rule can see it.
      {
        'root[""a]' => "a",
        'root["``"a]' => "a",
        'root[""""a]' => "a",
        'root[""a""]' => 'a""',
        'root["a"""]' => "a",
        'root["a""``"]' => "a",
        'root["""a"""]' => "a",
      }.each do |line, title|
        it "reads #{line.inspect} as #{title.inspect}" do
          source = "kanban\n  #{line}\n"
          expect(parser.parse(source).columns.first.title).to eq(title)
        end
      end

      it "refuses an empty quoted fragment with no text after it" do
        expect { parser.parse("kanban\n  root[\"\"]\n") }.to raise_error(Sirena::Parser::ParseError)
      end

      it "keeps a quoted bracket label that merely contains a backtick pair" do
        diagram = parser.parse("kanban\n  root[\"Hello `code` world\"]\n")
        expect(diagram.columns.first.title).to eq("Hello `code` world")
      end

      it "keeps an unquoted bracket label that starts with a backtick" do
        diagram = parser.parse("kanban\n  root[`Hello`]\n")
        expect(diagram.columns.first.title).to eq("`Hello`")
      end
    end

    context "with empty quoted fragments on a round-shaped item" do
      # Mermaid's NODE lexer drops these fragments for every delimiter shape,
      # not only for the bracket-labelled form exercised above.
      {
        'col(""a)' => "a",
        'col("``"a)' => "a",
        'col(""""a)' => "a",
        'col(""a"")' => 'a""',
        'col("a""")' => "a",
        'col("a""``")' => "a",
        'col("a""""``")' => "a",
        'col("""a""")' => "a",
        'col("""``""a""``""")' => "a",
        '(""a)' => "a",
      }.each do |line, title|
        it "reads #{line.inspect} as #{title.inspect}" do
          source = "kanban\n  #{line}\n"
          expect(parser.parse(source).columns.first.title).to eq(title)
        end
      end
    end

    context "with a shape-delimiter character " \
            "in an unquoted round-shaped label" do
      # Not from the corpus - a Codex-constructed input. `round_text`'s
      # unquoted alternative excluded only `)`, the shape's own closer, so
      # it accepted `(`, `]` and `}` too - mermaid's lexer treats all
      # three as node-shape delimiters even unquoted and rejects them
      # (measured against mmdc 11.12.0). `[` and `{` are not delimiters to
      # mermaid there, so they stay accepted on both sides.
      ["(", "]", "}"].each do |delimiter|
        it "refuses an unquoted label carrying a literal " \
           "#{delimiter.inspect}" do
          expect { parser.parse("kanban\n  col(a#{delimiter}b)\n") }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end

      ["[", "{"].each do |literal|
        it "keeps an unquoted label carrying a literal #{literal.inspect}" do
          diagram = parser.parse("kanban\n  col(a#{literal}b)\n")
          expect(diagram.columns.first.title).to eq("a#{literal}b")
        end
      end
    end

    context "with round-shaped items and a blank row together (corpus 031)" do
      let(:source) do
        "kanban\n  root(Root)\n    Child(Child)\n      " \
          "a(a)\n\n      b[New Stuff]\n"
      end

      it "keeps every card across the blank row" do
        diagram = parser.parse(source)
        expect(diagram.columns.map do |column|
          [column.id, column.title, column.cards.map(&:id),
           column.cards.map(&:text)]
        end).to eq([["root", "Root", %w[Child a b],
                     ["Child", "a", "New Stuff"]]])
      end
    end

    context "with a quoted bracket label containing the shape's own " \
            "delimiters (corpus 028, 029)" do
      # labelled_item's unquoted GreedyRun stopped at the FIRST `]`, which
      # for a body containing one is inside the quotes - well before the
      # real closing bracket - so the whole line failed to parse.
      it "keeps a literal bracket pair inside a quoted column label (corpus " \
         "028)" do
        diagram = parser.parse("kanban\n    root[\"String containing []\"]")
        expect([diagram.columns.map(&:id), diagram.columns.first.title])
          .to eq([["root"], "String containing []"])
      end

      it "keeps a literal bracket pair and a literal paren pair on a column " \
         "and its child (corpus 029)" do
        diagram = parser.parse(
          "kanban\n    root[\"String containing []\"]\n      child1[\"String " \
          "containing ()\"]",
        )
        column = diagram.columns.first
        expect([column.title, column.cards.map(&:id), column.cards.first.text])
          .to eq(["String containing []", ["child1"], "String containing ()"])
      end
    end

    context "with a standalone comment line between items (corpus 032)" do
      let(:source) do
        "kanban\n  root(Root)\n    Child(Child)\n      a(a)\n\n      %% This " \
          "is a comment\n      b[New Stuff]"
      end

      it "ignores the comment line and keeps every card around it" do
        diagram = parser.parse(source)
        column = diagram.columns.first
        expect([column.title, column.cards.map(&:id), column.cards.map(&:text)])
          .to eq(["Root", %w[Child a b], ["Child", "a", "New Stuff"]])
      end

      it "accepts JavaScript whitespace before the comment marker" do
        diagram = parser.parse("kanban\n\u00a0%% comment\n  root\n")
        expect(diagram.columns.map(&:id)).to eq(["root"])
      end
    end

    context "with a trailing comment on an item's own line (corpus 033)" do
      let(:source) do
        "kanban\n  root(Root)\n    Child(Child)\n      a(a) %% This is a " \
          "comment\n      b[New Stuff]"
      end

      it "strips the trailing comment and keeps the item itself" do
        diagram = parser.parse(source)
        column = diagram.columns.first
        expect([column.title, column.cards.map(&:id), column.cards.map(&:text)])
          .to eq(["Root", %w[Child a b], ["Child", "a", "New Stuff"]])
      end
    end

    # Measured against mmdc 11.12.0: a closing `]`, `)` or `}` ends the item,
    # so `%%` after it opens a comment with or without JavaScript whitespace
    # before it. After a bare id, `%%` - spaced or not - is part of the
    # literal label (`root %% c` renders that label), which Sirena refuses
    # rather than silently dropping the suffix.
    {
      "root[Root]%% c" => "Root",
      "root[Root] %% c" => "Root",
      "root[Root]\t%% c" => "Root",
      "root[Root]\u00a0%% c" => "Root",
      "root(Root)%% c" => "Root",
      "(Root)%% c" => "Root",
      "root[Root]@{ icon: star }%% c" => "Root",
      "root[Root]@{ icon: star }\u00a0%% c" => "Root",
      "root@{ icon: star } %% c" => "root",
      "root[Root]\u00a0" => "Root",
      "root[Root]@{ icon: star }\u00a0" => "Root",
      "root[Root]%%" => "Root",
    }.each do |line, title|
      context "with a trailing comment on #{line.inspect}" do
        it "keeps the item and drops the comment" do
          source = "kanban\n  #{line}\n"
          expect(parser.parse(source).columns.map(&:title)).to eq([title])
        end
      end
    end

    ["root%%keep", "root%% c", "root %% c", "root\t%% c", "root\u00a0%% c",
     "root\u00a0", "root \u00a0"].each do |line|
      context "with a bare item followed by `%%`: #{line.inspect}" do
        it "raises ParseError instead of silently dropping the suffix" do
          expect { parser.parse("kanban\n  #{line}\n") }.to raise_error(Sirena::Parser::ParseError)
        end
      end
    end

    # Measured against mmdc 11.12.0: `::icon(x)` returns to the initial lexer
    # state, so a comment may follow it; `:::cls` keeps `%%` as class text.
    ["::icon(x)%% c", "::icon(x) %% c", "::icon(x)\t%% c",
     "::icon(x)\u00a0%% c", "::icon(x)\u00a0"].each do |line|
      context "with a trailing comment on the icon modifier #{line.inspect}" do
        it "sets the icon and drops the comment" do
          diagram = parser.parse("kanban\n  root[Root]\n    #{line}\n")
          expect(diagram.columns.first.icon).to eq("x")
        end
      end
    end

    # Mermaid's `.*` comment body stops at U+2028/U+2029 and tokenizes what
    # follows; Sirena refuses rather than swallowing it into the comment.
    ["\u2028", "\u2029"].each do |separator|
      context "with a line separator #{separator.dump} inside a comment" do
        it "raises ParseError instead of dropping the text after it" do
          source = "kanban\n  root[Root]%% c#{separator}child[Child]\n"
          expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
        end
      end

      # A line holding only a comment is stripped up to its line feed, so
      # unlike a trailing comment its body runs through the separator
      # (mmdc 11.12.0).
      context "with #{separator.dump} inside a standalone comment line" do
        it "treats the text after it as comment" do
          source = "kanban\n  %% c#{separator}child[Child]\n  root\n"
          expect(parser.parse(source).columns.map(&:id)).to eq(["root"])
        end
      end
    end

    KanbanLineEndCases::PLACEMENTS.each do |placement, (template, cards, bad)|
      context "with a character #{placement}" do
        let(:source_for) { ->(char) { template.sub("<c>", char) } }
        let(:accepted) do
          KanbanLineEndCases::WHITESPACE.except(*bad)
        end
        let(:rejected) do
          refusals = KanbanLineEndCases::WHITESPACE.slice(*bad)
          next refusals if KanbanLineEndCases::TEXT_PLACEMENTS.include?(placement)

          refusals.merge(KanbanLineEndCases::NOT_WHITESPACE)
        end

        it "keeps the column and its cards for each whitespace character " \
           "mermaid accepts" do
          expect_boards(accepted, source_for, cards)
        end

        it "raises ParseError for each character mermaid refuses" do
          expect_refused(rejected, source_for)
        end
      end
    end

    # Mermaid accepts a separator after a trailing comment only when blank
    # lines and comments alone follow it to the end of the input. Sirena
    # accepts that, and also refuses `%% x<separator>y` at the end of the
    # input, which mermaid accepts (stricter, never looser).
    KanbanLineEndCases::SEPARATORS.each do |name|
      context "with #{name} ending a trailing comment" do
        let(:char) { KanbanLineEndCases::WHITESPACE.fetch(name) }

        KanbanLineEndCases::BLANKS_AFTER.each do |after|
          it "keeps the item when only #{after.inspect} follows" do
            expect(boards_of("kanban\n  root[Root]%% x#{char}#{after}"))
              .to eq([["root", []]])
          end
        end

        it "raises ParseError when a card line follows" do
          expect { parser.parse("kanban\n  root[Root]%% x#{char}\n    a[A]\n") }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end
    end

    # `%%{` opens a directive, which mermaid refuses on a line of its own
    # (mmdc 11.12.0); after an item it is an ordinary trailing comment.
    ["%%{foo}%%\n", "  %%{init: {}}%%\n", "%%{foo}\n"].each do |line|
      it "raises ParseError for the directive line #{line.inspect}" do
        expect { parser.parse("kanban\n#{line}  col[Todo]\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "accepts a %%{ comment after an item" do
      expect(boards_of("kanban\n  col[Todo] %%{x}\n")).to eq([["col", []]])
    end

    it "refuses an item on the header line, as before" do
      expect { parser.parse("kanban  root[Root]\n  second[Second]\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    # A blank row may hold any JavaScript whitespace, not only spaces and tabs.
    context "with a row holding only a whitespace character" do
      let(:source_for) do
        ->(char) { "kanban\n  root[Root]\n#{char}\n    a[A]\n#{char}" }
      end

      it "ignores it between items and at the end of the input" do
        spaces = KanbanLineEndCases::WHITESPACE.slice(*KanbanLineEndCases::EVERY_SPACE)
        expect_boards(spaces, source_for, %w[a])
      end

      it "raises ParseError for a character that is not whitespace" do
        expect_refused(KanbanLineEndCases::NOT_WHITESPACE, source_for)
      end
    end

    # A carriage return alone ends a line, as it does in mermaid.
    context "with lone carriage returns as line breaks" do
      it "reads the same board as line feeds" do
        diagram = parser.parse("kanban\r  root[Root]\r    a[A]\r")
        expect([diagram.columns.first.id,
                diagram.columns.first.cards.map(&:id)]).to eq(["root", %w[a]])
      end

      it "ends a trailing comment" do
        diagram = parser.parse("kanban\n  root[Root]%% c\r    a[A]\n")
        expect(diagram.columns.first.cards.map(&:id)).to eq(["a"])
      end

      it "ends a class modifier" do
        diagram = parser.parse("kanban\n  root[Root]\n    :::hot\r    a[A]\n")
        expect(diagram.columns.first.classes).to eq(["hot"])
      end
    end

    # The class body stops at U+2028/U+2029, where mermaid's `.+` stops.
    KanbanLineEndCases::SEPARATORS.each do |name|
      context "with #{name} after a class modifier" do
        let(:char) { KanbanLineEndCases::WHITESPACE.fetch(name) }

        it "ends the class text there and the line with it" do
          source = "kanban\n  root[Root]\n    :::hot#{char}\n    a[A]\n"
          diagram = parser.parse(source)
          expect(diagram.columns.first.classes).to eq(["hot"])
        end

        it "raises ParseError when more text follows on the line" do
          expect { parser.parse("kanban\n  root[Root]\n    :::ho#{char}t\n") }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end
    end

    # An empty `::icon()` decorates nothing and may sit anywhere; an empty
    # `:::` swallows its line break in mermaid, so only blank or comment
    # lines may follow it.
    context "with an empty icon modifier" do
      ["kanban\n  ::icon()\n  root[Root]\n",
       "kanban\n  root[Root]\n    ::icon()\n    a[A]",
       "kanban\n  root[Root]\n    ::icon() %% c\n    a[A]\n",
       "kanban\n  root[Root]\n    ::icon()\n\n    a[A]\n"].each do |source|
        it "parses #{source.inspect} and sets no icon" do
          expect(parser.parse(source).columns.first.icon).to be_nil
        end
      end
    end

    ["    :::\n", "    :::", "    :::\n\n", "    :::\n%% c\n", "    :::\n  \n",
     "    :::  \n"].each do |line|
      context "with an empty class modifier #{line.inspect} as the last line" do
        it "keeps the card and sets no classes" do
          diagram = parser.parse("kanban\n  root[Root]\n    a[A]\n#{line}")
          expect([diagram.columns.first.cards.map(&:id),
                  diagram.columns.first.classes]).to eq([%w[a], []])
        end
      end
    end

    ["    :::\n    b[B]\n", "    :::\n    :::x\n",
     "    :::\n      b[B]\n", "    :::\n    :::\n",
     "    :::\n    ::icon()\n"].each do |lines|
      context "with an empty class modifier followed by #{lines.inspect}" do
        it "raises ParseError, as mermaid joins the next line onto it" do
          expect { parser.parse("kanban\n  root[Root]\n    a[A]\n#{lines}") }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end
    end

    context "with many empty class modifiers in a row" do
      it "raises ParseError instead of exhausting the stack" do
        source = "kanban\n  root[Root]\n#{"    :::\n" * 400}"
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    context "with an empty class modifier before any item" do
      it "raises ParseError" do
        expect do
          parser.parse("kanban\n  :::\n  root[Root]\n")
        end.to raise_error(Sirena::Parser::ParseError)
      end
    end

    context "with `%%` straight after `:::`" do
      it "keeps it as class text rather than reading an empty modifier and a " \
         "comment" do
        diagram = parser.parse("kanban\n  root[Root]\n    :::%% c\n")
        expect(diagram.columns.first.classes).to eq(["%%", "c"])
      end
    end

    context "with `%%` after a class modifier" do
      it "keeps it as class text" do
        diagram = parser.parse("kanban\n  root[Root]\n    :::hot %% c\n")
        expect(diagram.columns.first.classes).to eq(["hot", "%%", "c"])
      end
    end

    context "with metadata spread across multiple lines (corpus 038)" do
      let(:source) do
        "kanban\n        root@{\n          icon: star\n          assigned: " \
          "knsv\n        }"
      end

      it "parses a newline-separated metadata block with no commas" do
        diagram = parser.parse(source)
        column = diagram.columns.first
        expect([column.id, column.icon]).to eq(%w[root star])
      end
    end

    # Measured against mmdc 11.12.0: `root@{ icon: star assigned: knsv }`
    # (same line, no comma between entries) is a YAMLException there -
    # mermaid never treats bare same-line whitespace as an entry separator,
    # only an actual newline (corpus 038's form, above) or a comma. Taking a
    # single space with no newline as a separator would silently accept what
    # mermaid rejects outright.
    context "with same-line metadata entries separated by whitespace but no " \
            "comma" do
      it "raises ParseError instead of accepting a separator mermaid rejects" do
        expect do
          parser.parse("kanban\n  root@{ icon: star assigned: knsv }\n")
        end.to raise_error(Sirena::Parser::ParseError)
      end
    end

    # The same bare-whitespace-with-no-comma separator is also rejected by
    # mmdc INSIDE block form (entries on their own lines, corpus 038's
    # shape), not only in flow form above - measured: `root@{\n  icon: star
    # assigned: knsv\n}` (two entries sharing one line, separated by a
    # single space) raises YAMLException in mmdc 11.12.0, so it must be
    # refused here too.
    context "with block-form entries sharing one line, separated by " \
            "whitespace but no comma" do
      it "raises ParseError instead of accepting a separator mermaid rejects" do
        expect do
          parser.parse("kanban\n  root@{\n    icon: star assigned: knsv\n  }\n")
        end.to raise_error(Sirena::Parser::ParseError)
      end
    end

    # A body is block YAML when it holds a newline anywhere, flow YAML
    # otherwise. Measured directly against mmdc 11.12.0: an inline-started
    # entry continued on a new line at a deeper indent - with or without a
    # trailing comma - and a body of several entries whose `}` is pushed to
    # its own line are each a YAMLException there. Aligned or single-entry
    # bodies are valid YAML and are accepted (see the acceptance table below).
    context "with an inline-started entry continued at a deeper indent, no " \
            "comma" do
      it "raises ParseError instead of accepting a form mermaid rejects" do
        source = "kanban\n  col[Todo]\n    task1[Do " \
                 "thing]@{ icon: star\n      assigned: knsv }\n"
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    context "with an inline-started entry continued at a deeper indent, with " \
            "a comma" do
      it "raises ParseError instead of accepting a form mermaid rejects" do
        source = "kanban\n  col[Todo]\n    task1[Do " \
                 "thing]@{ icon: star,\n      assigned: knsv }\n"
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    context "with several inline entries and the closing brace pushed to " \
            "its own line" do
      it "raises ParseError instead of accepting a form mermaid rejects" do
        source = "kanban\n  col[Todo]\n    task1[Do thing]@{ icon: star, " \
                 "assigned: knsv\n    }\n"
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    # A trailing comma at end of line is NOT a separator in block form -
    # mmdc's own YAML oracle (js-yaml, JSON_SCHEMA) keeps it as literal
    # scalar content, so `icon: star,` on its own line resolves to the
    # value "star,", not "star". Measured directly against js-yaml as
    # bundled with mmdc 11.12.0.
    context "with a card-level block-form metadata body, a trailing comma on " \
            "one entry" do
      it "keeps the comma as part of the value, matching mmdc" do
        source = "kanban\n  col[Todo]\n    task1[Do thing]@{\n      icon: " \
                 "star,\n      assigned: knsv\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect([card.icon, card.assigned]).to eq(["star,", "knsv"])
      end
    end

    context "with block-form entries sharing one line, separated by a comma" do
      it "raises ParseError instead of accepting a separator mermaid rejects" do
        expect do
          parser.parse("kanban\n  root@{\n    icon: star, assigned: knsv\n  " \
                       "}\n")
        end.to raise_error(Sirena::Parser::ParseError)
      end
    end

    context "with a card-level block-form metadata body, entries " \
            "newline-only" do
      it "parses every entry, matching mmdc" do
        source = "kanban\n  col[Todo]\n    task1[Do thing]@{\n      icon: " \
                 "star\n      assigned: knsv\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect([card.icon, card.assigned]).to eq(%w[star knsv])
      end
    end

    context "with blank and spaces-only rows (corpus 012 = 013 = 014)" do
      let(:source) { "kanban\nroot\n A\n \n\n B\n" }

      it "ignores the empty rows and keeps the bare nodes", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(["root"])
        expect(diagram.columns.first.cards.map(&:id)).to eq(%w[A B])
      end
    end

    context "with a node three levels deep (corpus 018)" do
      let(:source) do
        "kanban\n    root\n      child1\n        leaf1\n      child2\n"
      end

      it "flattens every deeper level into the column card list", :aggregate_failures do
        # Mermaid does not distinguish deeper levels here, and neither does
        # the builder: anything not at the first item's indent is a card.
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(["root"])
        expect(diagram.columns.first.cards.map(&:id))
          .to eq(%w[child1 leaf1 child2])
      end
    end

    context "with several bare sections (corpus 019)" do
      let(:source) { "kanban\n    section1\n    section2\n" }

      it "creates a column per section and no cards", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(%w[section1 section2])
        expect(diagram.columns.map { |c| c.cards.size }).to eq([0, 0])
      end
    end

    context "with bare and labelled columns together (corpus 002)" do
      let(:source) do
        # The corpus source verbatim: the same card id `docs` appears under
        # both columns, which is the shape this case exists to cover.
        "kanban\n  id1[Todo]\n    docs[Create Documentation]\n  " \
        "id2\n    docs[Create Blog about the new diagram]\n"
      end

      it "accepts both forms on one board", :aggregate_failures do
        diagram = parser.parse(source)
        expect(diagram.columns.map(&:id)).to eq(%w[id1 id2])
        expect(diagram.columns.map(&:title)).to eq(["Todo", "id2"])
      end

      it "keeps a repeated card id in its own column" do
        diagram = parser.parse(source)
        card_ids = diagram.columns.map { |column| column.cards.map(&:id) }

        expect(card_ids).to eq([["docs"], ["docs"]])
      end
    end

    context "with identical bare cards in one column" do
      # Bare cards make three look-alike lines trivial to write, and the
      # builder must keep one card per line. The corpus 002 example above
      # cannot cover it, because its two `docs` cards carry different text.
      it "keeps one card per line rather than collapsing look-alikes" do
        diagram = parser.parse("kanban\n  col\n    a\n    a\n    a\n")
        expect(diagram.columns.first.cards.map(&:id)).to eq(%w[a a a])
      end
    end

    # Mermaid's column level is the FIRST item's indent (kanbanDb getSection),
    # not the shallowest. Every row below was driven through mmdc 11.12.0.
    # A rejected row is rejected only once an item follows the shallower one.
    context "with the first item deeper than a later item" do
      [
        ["kanban\n    root[Root]\n  a[A]\n", [["Root", %w[A]]]],
        ["kanban\n  root[Root]\na[A]\n", [["Root", %w[A]]]],
        ["kanban\n  c1[C1]\n    k1[K1]\n experiment[E]\n",
         [["C1", %w[K1 E]]]],
        ["kanban\n  c1[C1]\n    k1[K1]\n  c2[C2]\n    k2[K2]\n experiment[E]\n",
         [["C1", %w[K1]], ["C2", %w[K2 E]]]],
      ].each do |source, expected|
        it "reads #{source.inspect} as #{expected.inspect}" do
          columns = parser.parse(source).columns

          expect(columns.map { |c| [c.title, c.cards.map(&:text)] })
            .to eq(expected)
        end
      end

      [
        "kanban\n    root[Root]\n  a[A]\n    b[B]\n",
        "kanban\n  c1[C1]\n    k1[K1]\nx[X]\n    k2[K2]\n",
        "kanban\n    c1[C1]\n  m[M]\n      k[K]\n",
        "kanban\n          root\n        fakeRoot\n    realRootWrongPlace\n",
      ].each do |source|
        it "rejects #{source.inspect}" do
          expect { parser.parse(source) }
            .to raise_error(Sirena::Parser::ParseError,
                            /Items without section detected/)
        end
      end

      it "names the shallower item, as mermaid does (corpus 020)" do
        source = ["kanban", "          root", "        fakeRoot",
                  "    realRootWrongPlace", ""].join("\n")

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError,
                          /found section \("fakeRoot"\)/)
      end

      it "names the shallower item by its label, not its id" do
        source = "kanban\n    root[Root]\n  a[A]\n    b[B]\n"

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError,
                          /found section \("A"\)/)
      end

      it "names the shallower item by its label: override" do
        source = "kanban\n    root[Root]\n  a[A]@{ label: Renamed }\n    b[B]\n"

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError,
                          /found section \("Renamed"\)/)
      end
    end

    context "with a label: override on a labelled column" do
      # Metadata beats bracket text, which is what mmdc renders for
      # `root[L]@{ label: xx }`. No corpus case covers the labelled shape -
      # 040 is bare - so it is pinned here.
      let(:source) { "kanban\n  id1[Todo]@{ label: 'Renamed' }\n" }

      it "prefers the label metadata over the bracket text" do
        expect(parser.parse(source).columns.first.title).to eq("Renamed")
      end
    end

    context "with an empty label:" do
      # An empty label is not a label. mmdc renders the bracket text for
      # `id1[Todo]@{ label: '' }`, and the id when there is no bracket text.
      it "falls back to the bracket text" do
        diagram = parser.parse("kanban\n  id1[Todo]@{ label: '' }\n")
        expect(diagram.columns.first.title).to eq("Todo")
      end

      it "falls back to the id when there is no bracket text" do
        diagram = parser.parse("kanban\n  id1@{ label: '' }\n")
        expect(diagram.columns.first.title).to eq("id1")
      end

      it "treats a double-quoted empty label the same way" do
        diagram = parser.parse(%(kanban\n  id1[Todo]@{ label: "" }\n))
        expect(diagram.columns.first.title).to eq("Todo")
      end

      # Whitespace is not empty, so this one does NOT fall back - it is the
      # single case that separates `.empty?` from `.strip.empty?`, and
      # stripping here would be wrong. Oracle-confirmed rather than
      # incidental: mmdc 11.12.0 emits `<span class="nodeLabel"></span>` -
      # empty, with no text node at all - where a kept label gives
      # `<p>x</p>` and a fallback gives the bracket text. So the label is
      # consumed rather than fallen back to; it just leaves nothing behind.
      it "keeps a whitespace-only label rather than falling back" do
        diagram = parser.parse("kanban\n  id1[Todo]@{ label: '   ' }\n")
        expect(diagram.columns.first.title).to eq("   ")
      end
    end

    context "with an icon/class directive line (corpus 024-027, 030)" do
      # `::icon(...)` and `:::classes` on their own line apply to the item
      # declared just above them - mermaid's shorthand for the same fields
      # `@{ icon: ... }` sets through metadata (classes has no `@{ }` key at
      # all; this directive is its only spelling). Mirrors mindmap.rb's
      # `node_with_icon` / `node_with_class`, already parsed the same way
      # there.
      it "sets the icon on the item above it (corpus 024)" do
        source = "kanban\n    root[The root]\n    ::icon(fa-house)\n"
        diagram = parser.parse(source)
        expect(diagram.columns.first.icon).to eq("fa-house")
      end

      it "sets classes on the item above it (corpus 025)" do
        diagram = parser.parse("kanban\n    root[The root]\n    :::m-4 p-8\n")
        expect(diagram.columns.first.classes).to eq(%w[m-4 p-8])
      end

      it "splits classes on whitespace regardless of $; " \
         "(Ruby global field separator)" do
        old_fs = $;
        $; = ","
        diagram = parser.parse("kanban\n    root[The root]\n    :::m-4 p-8\n")
        expect(diagram.columns.first.classes).to eq(%w[m-4 p-8])
      ensure
        $; = old_fs
      end

      it "accepts a class line followed by an icon line (corpus 026)", :aggregate_failures do
        diagram = parser.parse(class_then_icon_source)
        column = diagram.columns.first
        expect(column.classes).to eq(%w[m-4 p-8])
        expect(column.icon).to eq("fa-rocket")
      end

      it "accepts an icon line followed by a class line (corpus 027)", :aggregate_failures do
        diagram = parser.parse(icon_then_class_source)
        column = diagram.columns.first
        expect(column.icon).to eq("fa-flag")
        expect(column.classes).to eq(%w[m-4 p-8])
      end

      it "applies a class line to a card, " \
         "and a later card stays unaffected (corpus 030)", :aggregate_failures do
        source = "kanban\n  root(Root)\n    Child(Child)\n    " \
                 ":::hot\n      a(a)\n      b[New Stuff]\n"
        diagram = parser.parse(source)
        cards = diagram.columns.first.cards.to_h { |c| [c.id, c] }

        expect(cards.fetch("Child").classes).to eq(["hot"])
        expect(cards.fetch("a").classes).to eq([])
        expect(cards.fetch("b").classes).to eq([])
      end

      it "strips leading/trailing space around the class list " \
         "rather than splitting an empty entry" do
        source = "kanban\n    root[The root]\n    :::  m-4  p-8  \n"
        diagram = parser.parse(source)
        expect(diagram.columns.first.classes).to eq(%w[m-4 p-8])
      end

      # `:::` is last-write-wins, the same as `::icon`: mermaid's own
      # `decorateNode` plainly assigns `node.cssClasses = ...` on each
      # directive rather than merging with whatever classes the node
      # already carried (verified against the installed
      # @mermaid-js/mermaid-cli 11.12.0 kanban-definition bundle).
      {
        "a second `:::` line replaces the first" =>
          [
            "kanban\n    root[The root]\n    :::first\n    :::second\n",
            %w[second],
          ],
        "a `@{ classes: }` entry is ignored, the `:::` line wins" =>
          [
            "kanban\n    root[The root]@{ classes: 'existing' }\n    " \
            ":::added\n",
            %w[added],
          ],
        "a repeated identical class line has no visible effect" =>
          ["kanban\n    root[The root]\n    :::hot\n    :::hot\n", %w[hot]],
      }.each do |description, (source, expected)|
        it description do
          diagram = parser.parse(source)
          expect(diagram.columns.first.classes).to eq(expected)
        end
      end

      # mmdc 11.12.0 rejects an `::icon(...)`/`:::...` line with no item
      # above it to modify - it is not a valid empty diagram, so sirena
      # raises rather than silently dropping the directive.
      it "raises on an icon directive with no preceding item" do
        expect { parser.parse("kanban\n  ::icon(fa-orphan)\n") }
          .to raise_error(Sirena::Parser::ParseError, /::icon/)
      end

      it "raises on a class directive with no preceding item" do
        expect { parser.parse("kanban\n  :::hot\n") }
          .to raise_error(Sirena::Parser::ParseError, /:::/)
      end

      # mmdc 11.12.0 accepts a tab before the directive and trailing
      # horizontal whitespace after the closing `)` - both are ordinary
      # whitespace to its lexer. modifier_line used to require only spaces
      # before the directive and allowed nothing at all after it, so both
      # raised Sirena::Parser::ParseError.
      it "accepts a tab before the directive (mmdc 11.12.0)" do
        diagram = parser.parse("kanban\n    root[The root]\n\t::icon(fa-tab)\n")
        expect(diagram.columns.first.icon).to eq("fa-tab")
      end

      it "accepts trailing horizontal whitespace after the directive " \
         "(mmdc 11.12.0)" do
        source = "kanban\n    root[The root]\n    ::icon(fa-trail)   \n"
        diagram = parser.parse(source)
        expect(diagram.columns.first.icon).to eq("fa-trail")
      end

      # mmdc's lexer matches the `icon` keyword case-insensitively, the same
      # way kanban_keyword already does for the `kanban` header.
      it "accepts the icon directive spelled in a different case " \
         "(mmdc 11.12.0)" do
        source = "kanban\n    root[The root]\n    ::ICON(fa-case)\n"
        diagram = parser.parse(source)
        expect(diagram.columns.first.icon).to eq("fa-case")
      end
    end

    context "with a classes: entry in @{ } metadata" do
      # Mermaid's `addNode` reads shape/label/icon/assigned/ticket/priority
      # out of `@{ ... }` YAML and nothing else - `classes` is not a
      # recognized key there (verified against the installed
      # @mermaid-js/mermaid-cli 11.12.0 kanban-definition bundle). Only a
      # `:::` directive line may set classes; a `@{ classes: ... }` entry is
      # silently dropped, matching mermaid.
      it "ignores a classes: metadata value on a column" do
        diagram = parser.parse("kanban\n  root@{ classes: hot }\n")
        expect(diagram.columns.first.classes).to eq([])
      end

      it "ignores a classes: metadata value on a card" do
        source = "kanban\n  col[Todo]\n    " \
                 "card@{ classes: 'hot cold' }\n"
        diagram = parser.parse(source)
        expect(diagram.columns.first.cards.first.classes).to eq([])
      end
    end

    context "with metadata keys that collide with a card field" do
      # Mermaid ignores `id:`/`text:` as metadata; they are the card's own
      # fields. No corpus case uses them. The collision was already reachable
      # on base through a labelled card, which has always taken metadata -
      # the bare form only adds a second route to it. Reachable either way,
      # so neither route may emit wrong output.
      it "does not let text: overwrite the card text" do
        source = "kanban\n  col[C]\n    card[K]@{ text: 'CLOB' }\n"
        diagram = parser.parse(source)
        expect(diagram.columns.first.cards.first.text).to eq("K")
      end

      it "does not let id: overwrite the card id", :aggregate_failures do
        diagram = parser.parse("kanban\n  col[C]\n    card@{ id: 'CLOB' }\n")
        card = diagram.columns.first.cards.first
        expect(card.id).to eq("card")
        expect(card.text).to eq("card")
      end
    end

    context "with metadata on a bare card" do
      # The intersection of this bucket's two changes: a card with no bracket
      # label, carrying metadata.
      let(:source) { "kanban\n  col[Todo]\n    child1@{ assigned: knsv }\n" }

      it "titles the card by its id and keeps the metadata", :aggregate_failures do
        card = parser.parse(source).columns.first.cards.first
        expect(card.id).to eq("child1")
        expect(card.text).to eq("child1")
        expect(card.assigned).to eq("knsv")
      end
    end

    context "with the header token used as a node name" do
      # mmdc reserves `kanban` as a node name and refuses it in any case,
      # bare or labelled, as a column or a card. Only the whole word is
      # taken. No other keyword is reserved - measured against mmdc 11.12.0.
      it "refuses a bare kanban column" do
        expect { parser.parse("kanban\n  root[Root]\n  kanban\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "refuses a bare kanban card" do
        expect { parser.parse("kanban\n  root[Root]\n    kanban\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "refuses it whatever the case" do
        aggregate_failures do
          %w[Kanban KANBAN KaNbAn kAnBaN kanBan kanbaN].each do |word|
            expect { parser.parse("kanban\n  root[Root]\n  #{word}\n") }
              .to raise_error(Sirena::Parser::ParseError), word
          end
        end
      end

      it "refuses it even with a bracket label" do
        expect { parser.parse("kanban\n  root[Root]\n  kanban[Label]\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "accepts an id that merely contains the word" do
        # `kanban_x` is the case that matters: `_` is inside the boundary
        # class, so it continues the word rather than ending it. mermaid's
        # own `\b` agrees - it accepts `kanban_x` and rejects `kanban-x`.
        diagram = parser.parse(
          "kanban\n  root[Root]\n  kanbanBoard\n  mykanban\n  kanban_x\n",
        )
        expect(diagram.columns.map(&:title))
          .to eq(%w[Root kanbanBoard mykanban kanban_x])
      end

      it "reserves no other keyword" do
        # The single home of this list; the grammar comment points here.
        # Every token was probed against mmdc and parses as an ordinary node.
        others = %w[graph section title class classDef click style subgraph
                    accTitle accDescr end flowchart]
        body = others.map { |word| "  #{word}\n" }.join
        diagram = parser.parse("kanban\n  root[Root]\n#{body}")
        expect(diagram.columns.map(&:title)).to eq(["Root"] + others)
      end
    end

    context "with a metadata value mermaid resolves as falsy" do
      it "falls back for every spelling of zero" do
        # The signed forms carry the leading-sign branch of each radix
        # pattern, and `0e-0` the exponent's - the only sign the float
        # reaches, since `unquoted_value` admits `-` but not `+`.
        aggregate_failures do
          %w[0 -0 00 000 -00 0x0 0o0 0b0 0e0 0E0
             -0x0 -0o0 -0b0 0e-0].each do |zero|
            expect(title_for(zero)).to eq("A"), "expected #{zero} to be dropped"
          end
        end
      end

      it "falls back for false and null " \
         "in the three casings js-yaml resolves" do
        # lowercase, Capitalised and UPPERCASE - and no others.
        aggregate_failures do
          %w[false False FALSE null Null NULL].each do |word|
            expect(title_for(word)).to eq("A"), "expected #{word} to be dropped"
          end
        end
      end

      it "keeps other mixed-case spellings, which stay strings" do
        aggregate_failures do
          %w[fAlSe nUll].each do |word|
            expect(title_for(word)).to eq(word), "expected #{word} to be kept"
          end
        end
      end

      it "keeps an uppercase radix prefix, which js-yaml leaves as a string" do
        # All three prefixes are lowercase-only, so `0x0`/`0o0`/`0b0` are
        # zero while these stay strings. The exponent marker is the one
        # case-insensitive spelling, covered by `0E0` above.
        aggregate_failures do
          %w[0X0 0O0 0B0].each do |kept|
            expect(title_for(kept)).to eq(kept), "expected #{kept} to be kept"
          end
        end
      end

      it "keeps truthy scalars and quoted falsy-looking ones", :aggregate_failures do
        expect(title_for("1")).to eq("1")
        expect(title_for("true")).to eq("true")
        expect(title_for("'0'")).to eq("0")
        expect(title_for('"false"')).to eq("false")
      end

      it "reads the values a dot, plus or tilde makes" do
        # These three characters are new in the unquoted charset. Before
        # them the whole line raised a parse error, where mmdc 11.12.0 draws
        # the node. js-yaml resolves the first five falsy, so the title
        # falls back, and keeps the rest as numbers.
        aggregate_failures do
          %w[0.0 -0.0 +0 .nan ~].each do |zero|
            expect(title_for(zero)).to eq("A"), "expected #{zero} to be dropped"
          end
          { "1.5" => "1.5", "0.1" => "0.1", "+7" => "7" }.each do |text, drawn|
            message = "expected #{text} to draw #{drawn}"
            expect(title_for(text)).to eq(drawn), message
          end
        end
      end

      it "drops zero written with digit separators, including after a prefix" do
        # js-yaml honours `_` between digits, and `_` is in the unquoted
        # charset, so these reach here. A run of any length counts, and
        # `0x_0` shows one directly after a radix prefix.
        aggregate_failures do
          separated_zeroes.each do |zero|
            expect(title_for(zero)).to eq("A"), "expected #{zero} to be dropped"
          end
        end
      end

      it "strips the separators before converting, " \
         "so a non-zero payload survives" do
        # The other half of the separator rule, and the only half that can
        # tell stripping from tolerating. Every value in the drop example
        # above has a ZERO payload, where Ruby's own `to_i` already reaches
        # zero whether or not the separators are removed first - `0x_0` and
        # `0__0` are dropped either way. Only a NON-zero payload behind a
        # separator distinguishes them: without the strip, `to_i(16)` reads
        # `0x_1` as 0 and `to_i` truncates `0__1` at the double separator,
        # and both would be dropped where mermaid draws a label.
        #
        # mmdc 11.12.0 resolves each of these to a truthy number and keeps
        # the label row, drawn as the number: `0x_1` is 1, `0x_a` 10, `0x_10`
        # 16, `-0x_1` -1.
        drawn = {
          "0__1" => "1", "0___1" => "1", "-0__1" => "-1", "00__01" => "1",
          "0__10" => "10", "0x_1" => "1", "0x__1" => "1", "0x_10" => "16",
          "0x_a" => "10", "-0x_1" => "-1", "0x_0_1" => "1", "0o_1" => "1",
          "0o__1" => "1", "0o_10" => "8", "-0o_1" => "-1", "0o_0_1" => "1",
          "0b_1" => "1", "0b__1" => "1", "0b_10" => "2", "-0b_1" => "-1",
          "0b_0_1" => "1", "0__1e0" => "1", "0__1E0" => "1"
        }
        aggregate_failures do
          drawn.each do |text, expected|
            message = "expected #{text} to draw #{expected}"
            expect(title_for(text)).to eq(expected), message
          end
        end
      end

      it "keeps a separator that is not between digits" do
        # The boundary that makes this a rule rather than "delete every
        # underscore": leading, trailing, bridging a prefix, or standing
        # alone - mermaid keeps every one of these as a string.
        aggregate_failures do
          %w[_0 0_ __0 0_0_ -_0 _ 0_x0 _0e0].each do |kept|
            expect(title_for(kept)).to eq(kept), "expected #{kept} to be kept"
          end
        end
      end

      it "honours a separator anywhere in the mantissa, " \
         "trailing edge included" do
        # The float pattern is `[0-9][0-9_]*`, so a mantissa may even END in
        # separators - unlike the int pattern, where `0_` stays a string.
        aggregate_failures do
          %w[0_0e0 0_e0 0__e0 -0_e0 0_E0 0_0_e0].each do |zero|
            expect(title_for(zero)).to eq("A"), "expected #{zero} to be dropped"
          end
        end
      end

      it "ignores a separator inside the exponent" do
        # `_0e0` is not here: a leading separator is its own rule, covered by
        # the not-between-digits example above.
        aggregate_failures do
          %w[0e0_0 0e_0 0_e_0].each do |kept|
            expect(title_for(kept)).to eq(kept), "expected #{kept} to be kept"
          end
        end
      end

      it "keeps an integer that ends in a separator" do
        # Guards the int and float branches against being unified: widening
        # the float mantissa must not leak into the decimal case. Nothing is
        # refused here - the value survives verbatim as the title.
        aggregate_failures do
          expect(title_for("0_")).to eq("0_")
          expect(title_for("0_0_")).to eq("0_0_")
        end
      end

      it "drops a falsy value on each of the five gated fields, " \
         "and keeps a truthy one" do
        # The positive control matters: KanbanCard#metadata is a `.compact`
        # over five attributes, so an empty hash cannot by itself tell
        # "dropped" from "never parsed". The truthy row proves the fields do
        # land when mermaid would set them.
        falsy = "kanban\n  col[C]\n    k[K]@{ assigned: 0, ticket: false, " \
                "icon: null, priority: 0x0, label: '' }\n"
        truthy = "kanban\n  col[C]\n    k[K]@{ assigned: knsv, ticket: MC-1, " \
                 "icon: star, priority: High, label: 'Fix' }\n"

        aggregate_failures do
          card = parser.parse(falsy).columns.first.cards.first
          expect(card.metadata).to eq({})
          expect(card.text).to eq("K")

          kept = parser.parse(truthy).columns.first.cards.first
          expect(kept.metadata).to eq(
            assigned: "knsv", ticket: "MC-1", icon: "star",
            priority: "High", label: "Fix"
          )
        end
      end
    end

    # Parslet folds a repetition of plain slices with `Slice#+`, which copies
    # the string built so far on every step, and a rule that matches one
    # character at a time makes one slice per character: either is quadratic
    # in the input. Each row parses one family of inputs at SIZE and at four
    # times SIZE; linear growth gives a ratio near 4 and quadratic growth one
    # near 16, so the bound is 10: clear of both, and of timer noise on a
    # loaded machine. Families of lines carry long lines, and families of
    # runs long runs, because the copying only outweighs the per-piece cost
    # of the parser once the pieces are large. The timer floor keeps a parse
    # that takes a millisecond from inflating the ratio.
    context "with an input that grows" do
      fat = "x" * 3000
      half = "x" * 1500
      fat_space = " " * 3000
      {
        "standalone comment lines" =>
          [1_000, ->(n) { "kanban\n#{"  %% #{fat}\n" * n}" }],
        "standalone comment lines holding U+2028" =>
          [1_000, ->(n) { "kanban\n#{"  %% #{half}\u2028#{half}\n" * n}" }],
        "whitespace-only lines" =>
          [1_000, ->(n) { "kanban\n#{"#{fat_space}\n" * n}" }],
        "empty icon modifier lines" =>
          [1_000, ->(n) { "kanban\n#{"  ::icon()#{fat_space}\n" * n}" }],
        "comment lines after a U+2028 comment end" =>
          [1_000, ->(n) { "kanban\n  r[R] %% a\u2028\n#{"%% #{fat}\n" * n}" }],
        "comment lines after an empty class modifier" =>
          [1_000, ->(n) { "kanban\n  r[R]\n  :::\n#{"%% #{fat}\n" * n}" }],
        "metadata body lines" =>
          [1_000, ->(n) { "kanban\n  r[R]@{ a: 1\n#{"  #{fat}\n" * n}}\n" }],
        "comment lines inside metadata" =>
          [1_000, ->(n) { "kanban\n  r[R]@{ a: 1\n#{"%% #{fat}\n" * n}}\n" }],
        "lines inside a quoted metadata value" =>
          [1_000, ->(n) { "kanban\n  r[R]@{ a: \"x\n#{"#{fat}\n" * n}\" }\n" }],
        "non-ASCII entries on one metadata line" =>
          [8_000, lambda { |n|
            entries = Array.new(n) { |i| "k#{i}: é" }.join(", ")
            "kanban\n  r[R]@{ #{entries} }\n"
          }],
        "empty quoted fragments in a bracket label" =>
          [30_000, ->(n) { "kanban\n  r[#{'"``"' * n}a]\n" }],
        "empty quoted fragments in a round label" =>
          [30_000, ->(n) { "kanban\n  r(#{'"``"' * n}a)\n" }],
        "one long identifier" =>
          [50_000, ->(n) { "kanban\n  #{'x' * n}\n" }],
        "whitespace after an item" =>
          [60_000, ->(n) { "kanban\n  r[R]#{' ' * n}" }],
        "whitespace alone after the last line" =>
          [60_000, ->(n) { "kanban\n  r[R]\n#{' ' * n}" }],
        "whitespace before an item" =>
          [60_000, ->(n) { "kanban\n#{' ' * n}r[R]\n" }],
        "whitespace before a trailing comment" =>
          [60_000, ->(n) { "kanban\n  r[R]#{' ' * n}%% c\n" }],
        "a trailing comment body" =>
          [60_000, ->(n) { "kanban\n  r[R] %% #{'x' * n}\n" }],
        "a comment body after a U+2028 comment end" =>
          [60_000, ->(n) { "kanban\n  r[R] %% a\u2028 %% #{'x' * n}\n" }],
        "an icon body" =>
          [60_000, ->(n) { "kanban\n  r[R]\n  ::icon(#{'x' * n})\n" }],
        "a class body" =>
          [60_000, ->(n) { "kanban\n  r[R]\n  :::#{'x' * n}\n" }],
        "a bracket label" =>
          [60_000, ->(n) { "kanban\n  r[#{'x' * n}]\n" }],
        "a quoted bracket label" =>
          [60_000, ->(n) { "kanban\n  r[\"#{'x' * n}\"]\n" }],
        "a round label" =>
          [60_000, ->(n) { "kanban\n  r(#{'x' * n})\n" }],
        "item indentation" =>
          [60_000, ->(n) { "kanban\n#{' ' * n}r[R]\n" }],
        "an unquoted metadata value" =>
          [60_000, ->(n) { "kanban\n  r[R]@{ ticket: #{'x' * n} }\n" }],
        "whitespace between @ and the metadata brace" =>
          [60_000, ->(n) { "kanban\n  r[R]@#{' ' * n}{ ticket: T }\n" }],
        "a quoted metadata value" =>
          [150_000, ->(n) { "kanban\n  r[R]@{ ticket: \"#{'x' * n}\" }\n" }],
        "a quoted metadata value of escapes" =>
          [60_000, ->(n) { "kanban\n  r[R]@{ ticket: \"#{'\\n' * n}\" }\n" }],
        "a single-quoted metadata value" =>
          [150_000, ->(n) { "kanban\n  r[R]@{ ticket: '#{'x' * n}' }\n" }],
      }.each do |family, (size, build)|
        it "parses #{family} in time linear in their size", :speed do
          expect(growth_ratio(size, build)).to be < 10
        end
      end
    end

    # A rule that matches one character per `repeat` step allocates a parse
    # result per character, in linear time, so the timing ratios above cannot
    # see it. Counting allocated objects can: a `GreedyRun` allocates a fixed
    # handful however long the run.
    context "with a long run a per-character rule would allocate for" do
      def allocations_parsing(source)
        GC.start
        before = GC.stat(:total_allocated_objects)
        begin
          parser.parse(source)
        rescue Sirena::Parser::ParseError
          nil
        end
        GC.stat(:total_allocated_objects) - before
      end

      {
        "whitespace after a bare item" => "kanban\n  root#{' ' * 40_000}\n",
        "a bracket label opening with an unmatched backtick" =>
          "kanban\n  r[\"`#{'a' * 40_000}]\n",
        "a round label opening with an unmatched backtick" =>
          "kanban\n  r(\"`#{'a' * 40_000})\n",
        "a markdown-string bracket label" =>
          "kanban\n  r[\"`#{'a' * 40_000}`\"]\n",
      }.each do |family, source|
        it "allocates a bounded number of objects for #{family}" do
          expect(allocations_parsing(source)).to be < 10_000
        end
      end
    end

    # GreedyRun originally measured the run's length with
    # `Parslet::Source#matches?`, which reports BYTES (it delegates to
    # `StringScanner#match?`), then fed that byte count into
    # `Source#consume(n)`, which takes a CHARACTER count. On any multibyte
    # body the two units disagree, so the atom over-consumed past the real
    # closing delimiter and the parse failed outright - not a symptom, a
    # straight parse failure on legitimate Unicode input.
    context "with a multibyte label, icon or class body" do
      it "parses a label, icon and class body " \
         "containing multibyte characters", :aggregate_failures do
        label = parser.parse("kanban\n  id1[Todo]\n    root[café]\n")
          .columns.first.cards.first
        expect(label.text).to eq("café")

        icon = parser.parse(
          "kanban\n  id1[Todo]\n    root[Task]\n    ::icon(fa-café)\n",
        ).columns.first.cards.first
        expect(icon.icon).to eq("fa-café")

        classed = parser.parse(
          "kanban\n  id1[Todo]\n    root[Task]\n    :::café-class\n",
        ).columns.first.cards.first
        expect(classed.classes).to eq(["café-class"])
      end
    end

    # Driving this through the full grammar cannot isolate GreedyRun's
    # `break if remaining.zero?` loop guard: both `icon_modifier` and
    # `labelled_item` require a closing delimiter right after the match, so a
    # missing delimiter fails to parse for the same reason whether or not the
    # guard exists. Calling GreedyRun directly, with the exact char classes
    # those rules construct it with, exercises the guard itself.
    context "with an unterminated icon or bracket body, " \
            "GreedyRun called directly" do
      it "consumes to EOF without hanging, " \
         "using the icon_modifier char class", :aggregate_failures do
        result = nil
        expect do
          Timeout.timeout(2) { result = icon_greedy_run.parse("unterminated") }
        end.not_to raise_error
        expect(result.to_s).to eq("unterminated")
      end

      it "consumes to EOF without hanging, " \
         "using the labelled_item char class", :aggregate_failures do
        result = nil
        expect do
          Timeout.timeout(2) { result = label_greedy_run.parse("unterminated") }
        end.not_to raise_error
        expect(result.to_s).to eq("unterminated")
      end

      # Unlike icon and bracket bodies, a class body has no closing delimiter
      # at all - `:::classes` runs to end of line or EOF - so this shape
      # does not fail to parse; it exercises the same EOF-terminated loop
      # without hanging, which is the property this context is about.
      it "returns promptly (no closing delimiter to miss) " \
         "for a class body running to EOF" do
        source = "kanban\n  id1[Task]\n  :::unterminated"

        expect do
          Timeout.timeout(2) { parser.parse(source) }
        end.not_to raise_error
      end
    end

    # GreedyRun#try's `total.empty?` check (atoms/greedy_run.rb:59) turns a
    # zero-length match into a clean ParseError. `raise_error(ParseError)` on
    # a full parse cannot isolate it: `icon_modifier` requires a closing `)`
    # right after the body, so an empty body fails to parse for the same
    # reason with or without this guard. Calling GreedyRun directly on an
    # empty string exercises `total.empty?` itself.
    context "with an empty icon body" do
      it "raises Parslet::ParseFailed for GreedyRun's own empty match, " \
         "using the icon_modifier char class" do
        expect do
          Sirena::Parser::Atoms::GreedyRun.new("[^)]").parse("")
        end.to raise_error(Parslet::ParseFailed, empty_match_error)
      end
    end

    # `GreedyRun#to_s_inner` (atoms/greedy_run.rb:64) feeds
    # `Atoms::Base#to_s`, which Parslet calls to describe an unlabelled atom
    # (e.g. inside
    # `Alternative#error_msg`'s "Expected one of [...]" listing, built from
    # `alternatives.inspect` -> each atom's `#inspect` -> `#to_s` ->
    # `#to_s_inner`). Exercised here directly on the same `GreedyRun`
    # instance the grammar builds (`GreedyRun.new('[^)]')`, matching
    # `icon_modifier`'s own construction), rather than fishing the exact
    # instance back out of a failed parse tree.
    context "with GreedyRun#to_s_inner called directly" do
      it "describes the atom by its anchored regexp, " \
         "matching icon_modifier's construction" do
        atom = Sirena::Parser::Atoms::GreedyRun.new("[^)]")

        # Asserted as a literal string, not `Regexp.new(...).inspect`, so the
        # spec does not re-derive its own expectation using the same
        # construction the production code under test uses.
        expect(atom.to_s_inner(0)).to eq('/\A(?:[^)])*/m')
      end
    end

    # Each row goes through this parser, not through MetadataYaml or Psych
    # in isolation. One table, one property per row: does the pipeline
    # accept what mermaid accepts and reject what it rejects.
    metadata_acceptance_shapes = {
      "a block body with no space right after @{, two entries" => {
        source: "kanban\n  col[Todo]\n    task1[Task]@{icon: star\nassigned: " \
                "knsv\n}\n",
        fields: { icon: "star", assigned: "knsv" },
      },
      "an unquoted block value containing a literal space" => {
        source: "kanban\n  col[Todo]\n    task1[Task]@{\n      label: Fix " \
                "things\n    }\n",
        fields: { label: "Fix things" },
      },
    }

    metadata_acceptance_shapes.each do |description, expectation|
      it "parses every field mermaid would resolve, with #{description}" do
        card = parser.parse(expectation[:source]).columns.first.cards.first
        fields = expectation[:fields]
        expect(fields.to_h { |field, _| [field, card.public_send(field)] })
          .to eq(fields)
      end
    end

    # NEL, LS and PS are line breaks to Psych but ordinary text to js-yaml,
    # so mmdc 11.12.0 keeps them in a value, quoted or not.
    value_styles = {
      "double-quoted" => %("a%sb"),
      "single-quoted" => "'a%sb'",
      "unquoted" => "a%sb",
    }

    {
      "NEL" => "\u0085",
      "LS" => "\u2028",
      "PS" => "\u2029",
    }.each do |name, character|
      value_styles.each do |style, template|
        it "keeps a #{name} inside a #{style} value" do
          value = format(template, character)
          source = "kanban\n  col[Todo]\n    task1[Task]@{ assigned: " \
                   "#{value} }\n"
          card = parser.parse(source).columns.first.cards.first
          expect(card.assigned).to eq("a#{character}b")
        end
      end
    end

    context "with a private-use character beside a line-separator character" do
      it "keeps both exactly as written" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{ assigned: " \
                 "\"a\u2028b\ue000c\" }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.assigned).to eq("a\u2028b\ue000c")
      end
    end

    # An escape resolves to its character after the engine has read the
    # body, so it must not be mistaken for a swapped-in line separator.
    {
      "\\uE000" => "\ue000",
      "\\U0000E000" => "\ue000",
    }.each do |escape, character|
      context "with a #{escape} escape beside a line-separator character" do
        it "keeps the escaped character and the separator apart" do
          source = "kanban\n  col[Todo]\n    task1[Task]@{ assigned: " \
                   "\"a\u2028b\", ticket: \"#{escape}\" }\n"
          card = parser.parse(source).columns.first.cards.first
          expect([card.assigned, card.ticket])
            .to eq(["a\u2028b", character])
        end
      end
    end

    context "with every private-use character taken and a line separator" do
      it "raises ParseError instead of reading the separator wrongly" do
        taken = (0xE000..0xF8FF).map { |code| code.chr(Encoding::UTF_8) }.join
        source = "kanban\n  col[Todo]\n    task1[Task]@{ assigned: " \
                 "\"\u2028#{taken}\" }\n"
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /line break/)
      end
    end

    metadata_rejection_shapes = {
      "an empty block body" =>
        "kanban\n  col[Todo]\n    task1[Task]@{\n    }\n",
      "a tab-indented entry" => "kanban\n  col[Todo]\n    task1[Task]@{\n" \
                                "\tlabel: x\n    }\n",
      "a duplicate key" => "kanban\n  col[Todo]\n    task1[Task]@{\n      " \
                           "label: a\n      label: b\n    }\n",
      "an unbalanced double quote" => "kanban\n  col[Todo]\n    " \
                                      "task1[Task]@{ assigned: b\" }\n",
      "a caret outside a quoted value" => "kanban\n  col[Todo]\n    " \
                                          "task1[Task]@{ icon: a^b }\n",
    }

    metadata_rejection_shapes.each do |description, source|
      it "raises ParseError instead of accepting a shape mermaid rejects, " \
         "with #{description}" do
        expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    # Mermaid reads properties from a sequence without finding any, so the
    # document is accepted as a metadata no-op rather than rejected.
    context "with a metadata body that resolves to a sequence, not a mapping" do
      it "accepts the body without assigning any metadata" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      - a\n      - " \
                 "b\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.metadata).to be_empty
      end

      it "does not read a sequence of keys as fields" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      - " \
                 "[assigned, leak]\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect([card.text, card.assigned]).to eq(["Task", nil])
      end
    end

    # Mermaid calls `.toString()` on an assigned, ticket or icon value and
    # keeps a label as written, so a list or map there is drawn as text, not
    # refused: `[one, two]` is "one,two" and a map is "[object Object]".
    # Each text below is what mmdc 11.12.0 drew for the same body. A flow
    # map cannot be spelled at all: the first `}` closes the `@{ }` body,
    # as in mermaid, so the grammar refuses it before this rule is reached.
    collection_texts = {
      "a flow list" => ["[one, two]", "one,two"],
      "a flow list of one number" => ["[1]", "1"],
      "an empty flow list" => ["[]", ""],
      "a nested list" => ["[[a], b]", "a,b"],
      "an empty list beside a scalar" => ["[[], a]", ",a"],
      "a list holding null" => ["[a, null]", "a,"],
      "a list of booleans" => ["[true, false]", "true,false"],
      "a list of numbers" => ["[1.5, 0x10, 1e3, .nan]", "1.5,16,1000,NaN"],
      "a block map" => ["\n        a: b", "[object Object]"],
      "a block list" => ["\n        - a\n        - b", "a,b"],
      "a block list of maps" =>
        ["\n        - a: 1\n        - b: 2",
         "[object Object],[object Object]"],
      "a list that holds itself" => ["\n        &a\n        - x\n        - *a",
                                     "x,"],
    }

    %w[assigned ticket icon].each do |key|
      collection_texts.each do |description, (value, text)|
        it "stores #{description} under #{key} as #{text.inspect}" do
          expect(card_of(key, value).public_send(key)).to eq(text)
        end
      end
    end

    collection_texts.each do |description, (value, text)|
      it "titles a column from #{description} as #{text.inspect}" do
        expect(column_of("label", value).title).to eq(text)
      end
    end

    # An alias repeats a list by reference, so a short body can spell
    # millions of items to join. `Source::Frontmatter` bounds its own alias
    # expansion the same way, and the same bodies are refused here that
    # mmdc would still draw.
    context "with a list that an alias repeats" do
      let(:most) { (["x"] * 10_000).join(", ") }

      it "refuses an expansion of millions of items without building it" do
        expect do
          Timeout.timeout(5) { parser.parse(alias_expansion_source(8)) }
        end.to raise_error(Sirena::Parser::ParseError, /too large/)
      end

      it "does not join the lists that only sit under unread keys" do
        source = alias_expansion_source(8, assigned: false)
        expect(Timeout.timeout(5) { parsed_card(source).metadata })
          .to be_empty
      end

      it "joins a list that an alias repeats a few times" do
        expect(parsed_card(alias_expansion_source(3)).assigned.count(","))
          .to eq((9**3) - 1)
      end

      it "joins a list of exactly the permitted size" do
        expect(card_of("assigned", "[#{most}]").assigned.count(","))
          .to eq(9_999)
      end

      it "refuses a list one item over the permitted size" do
        expect { card_of("assigned", "[#{most}, x]") }
          .to raise_error(Sirena::Parser::ParseError, /too large/)
      end

      it "ignores a list over the permitted size under an unread key" do
        expect(card_of("tags", "[#{most}, x]").metadata).to be_empty
      end

      it "counts the items of every field in the body together" do
        half = (["x"] * 6_000).join(", ")
        body = " assigned: [#{half}], ticket: [#{half}] "
        source = "kanban\n  col[Todo]\n    task1[Task]@{#{body}}\n"
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /too large/)
      end

      it "joins a list nested as deep as permitted" do
        expect(parsed_card(alias_chain_source(256)).assigned).to eq("x")
      end

      it "refuses a list nested one level deeper" do
        expect { parser.parse(alias_chain_source(257)) }
          .to raise_error(Sirena::Parser::ParseError, /nested too deeply/)
      end

      it "refuses a list nested thousands deep without exhausting the stack" do
        expect { parser.parse(alias_chain_source(5_000)) }
          .to raise_error(Sirena::Parser::ParseError, /nested too deeply/)
      end
    end

    # Mermaid ignores a key it does not read, whatever the value, and
    # compares `priority` by identity: a list is truthy but never one of the
    # named priorities, so `[High]` is not `High`.
    context "with a list or map under a key mermaid does not draw as text" do
      it "ignores an unknown key" do
        expect(card_of("tags", "[a, b]").metadata).to be_empty
      end

      it "ignores a map under an unknown key" do
        expect(card_of("tags", "\n        a: b").metadata).to be_empty
      end

      it "ignores a list under classes" do
        expect(card_of("classes", "[a, b]").classes).to eq([])
      end

      ["[High]", "[]", "\n        a: b", "\n        - High"].each do |value|
        it "does not read #{value.inspect} as a priority" do
          expect(card_of("priority", value).priority).to be_nil
        end
      end

      it "still reads a scalar priority" do
        expect(card_of("priority", "High").priority).to eq("High")
      end
    end

    # Mermaid lowercases the shape to compare it, which a list or map cannot
    # do, so it refuses the source (mmdc 11.12.0, for every value below).
    context "with a list or map under shape" do
      ["[rect]", "[]", "\n        a: b", "\n        - rect"].each do |value|
        it "raises ParseError on a card with #{value.inspect}" do
          expect { card_of("shape", value) }
            .to raise_error(Sirena::Parser::ParseError, /shape/i)
        end

        it "raises ParseError on a column with #{value.inspect}" do
          expect { column_of("shape", value) }
            .to raise_error(Sirena::Parser::ParseError, /shape/i)
        end
      end
    end

    context "with plain scalar metadata values" do
      it "keeps accepting text, number and boolean values" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{ assigned: knsv, " \
                 "priority: 3, ticket: true }\n"
        card = parser.parse(source).columns.first.cards.first
        expect([card.assigned, card.priority,
                card.ticket]).to eq(%w[knsv 3 true])
      end
    end

    context "with an unusable shape metadata value" do
      it "rejects values on which Mermaid cannot perform its shape checks" do
        ["RECT", "foo_bar", "kanbanItem", "[rect]", "1"].each do |value|
          source = "kanban\n  col[Todo]\n    task1[Task]@{ shape: #{value} }\n"
          expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
        end
      end
    end

    context "with a usable shape metadata value" do
      it "keeps parsing a lowercase shape name beside the card text" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{ shape: rect, " \
                 "assigned: knsv }\n"
        card = parser.parse(source).columns.first.cards.first
        expect([card.text, card.assigned]).to eq(%w[Task knsv])
      end
    end

    context "with a source that is not tagged UTF-8" do
      # The grammar and builder regexps carry non-ASCII character classes,
      # which raise Encoding::CompatibilityError against a binary or
      # ISO-8859-1 string that holds a non-ASCII byte.
      let(:source) { "kanban\n  col[Todo]\n    task1[Task\u00E9]\n" }

      it "parses a binary string with an accented label" do
        card = parser.parse(source.b).columns.first.cards.first
        expect(card.text).to eq("Task\u00E9")
      end

      it "reads a US-ASCII-tagged string as UTF-8, like a binary one" do
        ascii = source.dup.force_encoding("US-ASCII")
        card = parser.parse(ascii).columns.first.cards.first
        expect(card.text).to eq("Task\u00E9")
      end

      # `String#encode` leaves these four tagged UTF-8 with some invalid byte
      # runs unreplaced; each row is a run found by fuzzing that does.
      {
        "CESU-8" => [211, 226, 151, 188],
        "UTF8-DoCoMo" => [243, 243, 208, 175],
        "UTF8-KDDI" => [6, 228, 223, 196, 165],
        "UTF8-SoftBank" => [232, 183, 199, 162],
      }.each do |name, bytes|
        it "parses a #{name} string with an invalid byte run" do
          head = "kanban\n  col[Todo]\n    task1[Task".b
          bad = head + bytes.pack("C*") + "]\n".b
          tagged = bad.force_encoding(name)
          card = parser.parse(tagged).columns.first.cards.first
          expect(card.text).to start_with("Task")
        end
      end

      it "parses an ISO-8859-1 string with an accented label" do
        latin1 = source.encode("ISO-8859-1")
        expect(parser.parse(latin1).columns.first.cards.first.text)
          .to eq("Task\u00E9")
      end

      # The metadata body reaches the YAML engine as a String of its own, so
      # it must carry the same UTF-8 tag the label rules were matched on.
      {
        "binary" => :b.to_proc,
        "ISO-8859-1" => ->(text) { text.encode("ISO-8859-1") },
      }.each do |name, retag|
        it "parses an accented metadata value in a #{name} string" do
          text = "kanban\n  col[Todo]\n    task1[Task]@{ assigned: b\u00E9 }\n"
          card = parser.parse(retag.call(text)).columns.first.cards.first
          expect(card.assigned).to eq("b\u00E9")
        end
      end

      %w[UTF-7 ISO-2022-JP-2].each do |name|
        it "refuses #{name} strings (no UTF-8 converter) with a ParseError" do
          expect { parser.parse(source.dup.force_encoding(name)) }
            .to raise_error(Sirena::Parser::ParseError, /#{name}/)
        end
      end
    end

    context "with a UTF-8 string that holds an invalid byte" do
      it "replaces the byte instead of raising ArgumentError from Parslet" do
        source = (+"kanban\n  todo[T\xFF]\n").force_encoding("UTF-8")
        expect(parser.parse(source).columns.first.title).to eq("T�")
      end
    end

    context "with a source that is not a String" do
      [nil, 42].each do |value|
        it "raises ArgumentError for #{value.inspect}" do
          expect do
            parser.parse(value)
          end.to raise_error(ArgumentError, /must be a String/)
        end
      end
    end

    context "with a metadata body that resolves to nothing" do
      it "refuses a body that is only a YAML null" do
        expect { parser.parse("kanban\n  col[Todo]\n    a[x]@{\n~\n}\n") }
          .to raise_error(Sirena::Parser::ParseError, "Empty metadata.")
      end

      it "accepts a body that is a bare scalar as a no-op" do
        source = "kanban\n  col[Todo]\n    a[x]@{\nfoo\n}\n"
        card = parser.parse(source).columns.first.cards.first
        fields = [card.text, card.assigned, card.ticket, card.icon,
                  card.priority]
        expect(fields).to eq(["x", nil, nil, nil, nil])
      end
    end

    # `%%` comment lines inside a block-form body are stripped before the
    # body reaches MetadataYaml, the same as Builders::Flowchart's own
    # metadata bodies - a comment line between two real entries must not
    # break the parse or swallow either entry.
    context "with a %% comment line inside a block-form metadata body" do
      it "strips the comment and keeps both real entries" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      icon: star" \
                 "\n      %% a comment\n      assigned: knsv\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect([card.icon, card.assigned]).to eq(%w[star knsv])
      end

      it "recognizes JavaScript whitespace before the comment marker" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n\u00a0%% a " \
                 "comment\n      assigned: knsv\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.assigned).to eq("knsv")
      end
    end

    # A comment line is stripped whole, so a brace, a quote or a caret in
    # its text must not end the body or open a string (mmdc accepts each).
    {
      "a closing brace" => "%% note } here",
      "a double quote" => "%% note \" here",
      "a caret" => "%% note ^ here",
    }.each do |character, comment|
      context "with a %% comment line holding #{character}" do
        it "strips the comment and keeps both real entries" do
          source = "kanban\n  col[Todo]\n    task1[Task]@{\n      icon: star" \
                   "\n      #{comment}\n      assigned: knsv\n    }\n"
          card = parser.parse(source).columns.first.cards.first
          expect([card.icon, card.assigned]).to eq(%w[star knsv])
        end
      end
    end

    context "with a %% comment line holding a double quote inside a " \
            "multiline quoted value" do
      it "strips the comment and joins the value lines" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      assigned: " \
                 "\"a\n      %% it \" here\n      b\"\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.assigned).to eq("a<br/>b")
      end
    end

    # The anchor is node metadata, never part of the scalar's own text:
    # `&a 5` stores "5", not "&a 5".
    context "with an anchored plain scalar value" do
      it "resolves the value without the anchor marker leaking into it" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      icon: &a 5" \
                 "\n      priority: *a\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect([card.icon, card.priority]).to eq(%w[5 5])
      end
    end

    # A plain scalar folded across multiple lines - `icon: star\n  more` -
    # is stored as the YAML-resolved, space-joined string.
    context "with a plain scalar folded across two lines" do
      it "stores the YAML-resolved, space-joined value" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      icon: star" \
                 "\n        more\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.icon).to eq("star more")
      end
    end

    # A non-scalar mapping key (`[a, b]: ...`) is legal YAML - js-yaml
    # reads it via its own key-to-string rule - but never spells a known
    # kanban field name, so it is ignored and the parse must not crash.
    context "with a non-scalar mapping key in metadata" do
      it "reads the sibling scalar field and assigns nothing for the unknown " \
         "key" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      [a, b]: " \
                 "star\n      icon: fa-star\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.icon).to eq("fa-star")
      end
    end

    context "with an explicitly tagged plain metadata scalar" do
      it "stores the resolved value without the YAML tag source text" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      assigned: " \
                 "!!str false\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.assigned).to eq("false")
      end
    end

    context "with a double-quoted metadata scalar spanning lines" do
      it "preserves Mermaid lexer line breaks in the resolved value" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{\n      assigned: " \
                 "\"one\n        two\"\n    }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.assigned).to eq("one<br/>two")
      end
    end

    context "with a YAML version directive accepted by js-yaml" do
      it "reads the metadata" do
        source = "kanban\n  col[Todo]\n    task1[Task]@{%YAML 1.3\n---\n" \
                 "assigned: knsv\n}\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.assigned).to eq("knsv")
      end
    end

    # What `assigned: <value>` stores. Mermaid skips a key whose resolved
    # value is JavaScript-falsy (one row per resolved type: null, false,
    # integer zero, float zero, NaN, empty string). A number or boolean is
    # stored as JavaScript prints the resolved value; any other unquoted
    # scalar is stored as written, and a quoted one as its resolved string.
    assigned_outcomes = {
      "a YAML null" => ["~", nil],
      "false" => ["false", nil],
      "an integer zero" => ["0", nil],
      "a hex zero" => ["0x0", nil],
      "a float zero" => ["0.0", nil],
      "a negative float zero" => ["-0.0", nil],
      "NaN" => [".nan", nil],
      "an empty single-quoted string" => ["''", nil],
      "an empty double-quoted string" => ['""', nil],
      "a negative integer" => ["-1", "-1"],
      "a fractional float" => ["0.5", "0.5"],
      "an infinity" => [".inf", "Infinity"],
      "a whitespace-only string" => ["' '", " "],
      "a word" => %w[knsv knsv],
      "a hex integer" => ["0x1F", "31"],
      "a digit-grouped integer" => ["1_000", "1000"],
      "a trailing-zero float" => ["1.50", "1.5"],
      "an exponent float" => ["1e3", "1000"],
      "a quoted hex-looking string" => ["'0x1F'", "0x1F"],
      "a quoted float-looking string" => ['"1.50"', "1.50"],
      "a tagged hex integer" => ["!!int 0x1F", "31"],
      "a tagged whole float" => ["!!float 1.0", "1"],
      "a tagged large float" => ["!!float 1e21", "1e+21"],
    }

    assigned_outcomes.each do |description, (value, expected)|
      it "stores #{expected.inspect} for #{description}" do
        source = "kanban\n  col[Todo]\n    k[K]@{ assigned: #{value} }\n"
        card = parser.parse(source).columns.first.cards.first
        expect(card.assigned).to eq(expected)
      end
    end

    # An untyped `!!map` with no content composes to an empty mapping from a
    # scalar node.
    context "with a body that is only an empty !!map tag" do
      it "accepts the body without assigning any metadata" do
        source = "kanban\n  col[Todo]\n    k[K]@{\n!!map\n}\n"
        card = parser.parse(source).columns.first.cards.first
        expect([card.text, card.metadata]).to eq(["K", {}])
      end
    end

    # `metadata_entries` is public API released in 0.1.0: a subclass that
    # overrides it must still decide what the `@{ }` block yields.
    context "with a grammar subclass that overrides metadata_entries" do
      let(:grammar) do
        Class.new(Sirena::Parser::Grammars::Kanban) do
          rule(:metadata_entries) { space? >> str("zzz").as(:custom) >> space? }
        end.new
      end

      it "holds the override output as the item metadata" do
        tree = grammar.parse("kanban\n  card[Card]@{ zzz }\n")
        expect(tree[:lines].first[:metadata]).to eq(custom: "zzz")
      end
    end

    # Released in 0.1.0 and named in a comment on the grammar: a rename or
    # deletion breaks every subclass that builds on them.
    %w[
      metadata_entries metadata_entry metadata_key metadata_value
      unquoted_value
    ].each do |name|
      it "keeps #{name} as a public grammar rule" do
        expect(Sirena::Parser::Grammars::Kanban.new).to respond_to(name)
      end
    end

    context "with the unquoted_value grammar rule" do
      let(:rule) { Sirena::Parser::Grammars::Kanban.new.send(:unquoted_value) }

      it "keeps the :unquoted parse-tree capture name" do
        expect(rule.parse("alpha_1-2")).to eq(unquoted: "alpha_1-2")
      end

      it "keeps the dot, plus and tilde characters" do
        expect(rule.parse("alpha+1.5~")).to eq(unquoted: "alpha+1.5~")
      end
    end

    # The capture shape sirena 0.1.0 released, inherited from
    # `Grammars::Common`: a quoted run is captured one repeat at a time, so
    # an empty one is `[]`, not an empty slice. A run-based override of
    # `quoted_string` here would change that shape for every subclass that
    # builds on `metadata_value`.
    context "with the metadata_value grammar rule on a quoted value" do
      let(:rule) { Sirena::Parser::Grammars::Kanban.new.send(:metadata_value) }

      ['"', "'"].each do |quote|
        it "captures a #{quote}-quoted value as :string" do
          expect(rule.parse("#{quote}alpha beta#{quote}"))
            .to eq(string: "alpha beta")
        end

        it "captures a #{quote}-quoted value as one slice" do
          expect(rule.parse("#{quote}alpha beta#{quote}")[:string])
            .to be_a(Parslet::Slice)
        end

        it "captures an empty #{quote}-quoted value as an empty repeat" do
          expect(rule.parse("#{quote}#{quote}")).to eq(string: [])
        end

        it "keeps an escaped #{quote} inside the :string capture" do
          expect(rule.parse("#{quote}a\\#{quote}b#{quote}"))
            .to eq(string: "a\\#{quote}b")
        end
      end
    end
  end
end
