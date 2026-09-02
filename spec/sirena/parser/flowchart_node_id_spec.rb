# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  # Spelled out rather than read from the grammar: driving the examples off
  # the grammar's own constant means DELETING a word silently deletes its
  # test. The first example in that block pins the two lists against each
  # other, so adding or removing a reserved word fails loudly.
  #
  # A group method rather than a constant: a constant assigned inside a
  # block lands on Object however it is written here, so it would leak to
  # every other spec file. This is reachable both at group level, where the
  # examples are generated, and from inside one.
  def self.expected_reserved_words
    %w[
      swimlane-beta interpolate flowchart linkStyle subgraph classDef
      _parent _blank _self graph style class _top end
    ].freeze
  end

  def node_ids(source)
    described_class.new.parse(source).nodes.map(&:id).sort
  end

  def parses?(source)
    described_class.new.parse(source)
    true
  rescue Sirena::Parser::ParseError
    false
  end

  # Every flowchart subgraph is refused downstream of the grammar — the
  # diagram model has no container to put one in — so `parses?` cannot
  # tell a subgraph name this grammar accepts from one it rejects. The
  # name guards are the grammar's job and this asks the grammar directly.
  # The bracketed title a subgraph header captured, or nil. The name
  # itself is consumed rather than kept, so the title is what a header's
  # reading can be read back from.
  def subgraph_title_of(source)
    tree = Sirena::Parser::Grammars::Flowchart.new.parse(source)
    header = tree.find do |element|
      element.is_a?(Hash) && element.key?(:subgraph_id)
    end

    header[:subgraph_title]&.to_s
  end

  def subgraph_name_parses?(source)
    Sirena::Parser::Grammars::Flowchart.new.parse(source)
    true
  rescue Parslet::ParseFailed
    false
  end

  describe "node ids mermaid accepts" do
    # Sirena required a programming identifier — a letter or underscore,
    # then word characters. Mermaid is far wider, and every one of these
    # renders in mmdc 11.12.0.
    {
      "a bare digit" => "1",
      "a digit-led name" => "2FunctionArg",
      "a hex-looking name" => "9e122290",
      "a hyphen inside" => "a-b",
      "a dot inside" => "a.b",
      "a decimal" => "1.5",
      "a slash inside" => "a/b"
    }.each do |label, id|
      it "accepts #{label}" do
        expect(node_ids("flowchart TD\n  #{id} --> B\n")).to eq([id, "B"].sort)
      end
    end

    it "still accepts an ordinary identifier" do
      expect(node_ids("flowchart TD\n  A_1 --> B\n")).to eq(%w[A_1 B])
    end
  end

  describe "ids mermaid lexes as keywords" do
    # The characters are legal but mermaid's lexer finds a keyword, so
    # these are not node ids however wide the charset is.
    ["end. --> Z", "1end --> Z"].each do |statement|
      it "rejects #{statement.inspect}" do
        expect { described_class.new.parse("graph TD\n#{statement}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    # Only a place where mermaid's lexer restarts collides with the word
    # behind it. An ordinary id character in front settles the hunt, so
    # every spelling below is a plain id.
    %w[endpoint aend xend myend ending end1 end_x].each do |id|
      it "accepts #{id}" do
        expect(node_ids("graph TD\n#{id} --> Z\n")).to eq(["Z", id].sort)
      end
    end
  end

  describe "a hyphen next to an arrow" do
    # The hyphen is only part of an id when an arrow cannot start there.
    # Without that, `A-->B` read as a node called `A--` and a stray `>`.
    {
      "plain arrow" => "A-->B",
      "open link" => "A---B",
      "dotted arrow" => "A-.->B",
      "thick arrow" => "A==>B"
    }.each do |label, statement|
      it "splits a #{label} into two nodes" do
        expect(node_ids("graph TD\n#{statement}\n")).to eq(%w[A B])
      end
    end

    it "keeps a hyphenated id together when no arrow follows" do
      expect(node_ids("graph TD\na-b --> c-d\n")).to eq(%w[a-b c-d])
    end

    # Excluding x, o and > as well rejected these, which mermaid renders.
    { "a-o-->B" => %w[B a-o], "a-x-->B" => %w[B a-x] }.each do |src, ids|
      it "keeps #{src.split('--').first} together in #{src}" do
        expect(node_ids("graph TD\n#{src}\n")).to eq(ids)
      end
    end

    # mmdc refuses every `->` form, whatever the spacing. Only the two
    # unspaced ones were pinned, and `plain_arrow` listed a bare `->` as a
    # link, so `A -> B` and `A ->B` drew an edge mermaid never draws.
    ["A->B", "A -> B", "A ->B", "A-> B"].each do |statement|
      it "refuses #{statement.inspect}, as mermaid does" do
        expect { described_class.new.parse("graph TD\n#{statement}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  # Mermaid's plain link is `--+[-xo>]` — two or more dashes, then one of
  # `-`, `x`, `o`, `>` — so its LENGTH is not fixed. Spelling it as the two
  # strings `-->` and `---` was wrong in both directions.
  describe "how many dashes make a link" do
    # A fourth dash used to fall through to the widened id rule, which now
    # takes a bare `-`, so `A----B` drew an edge to a node called `-B` and
    # `A----` drew one to a node called `-`. mmdc draws A to B, and refuses
    # `A----` outright.
    { "A---B" => %w[A B], "A----B" => %w[A B], "A-----B" => %w[A B],
      "A--->B" => %w[A B], "A---->B" => %w[A B],
      "A-->B" => %w[A B] }.each do |statement, ids|
      it "reads #{statement} as one link between #{ids.join(' and ')}" do
        expect(node_ids("graph TD\n#{statement}\n")).to eq(ids)
      end
    end

    # Two ways to fall off the rule, both of which mmdc refuses too: a
    # link with nothing behind it, and a run too short to be a link.
    { "A----" => "has no target", "A---" => "has no target",
      "A-->" => "has no target",
      "A--B" => "is only two dashes",
      "A--" => "is only two dashes" }.each do |statement, reason|
      it "refuses #{statement}, which #{reason}" do
        expect(parses?("graph TD\n#{statement}\n")).to be(false)
      end
    end
  end

  # Measured against mmdc 11.12.0: two equals is too short to be a link, so
  # `A==B` is refused exactly as `A--B` is. Three or more draw a thick edge,
  # carrying an arrowhead only when the link itself has one.
  #
  # The headless forms used to be refused here, because every edge got an
  # arrowhead and drawing one where mermaid draws none is worse than
  # refusing. Link types now carry the arrowhead separately and a headless
  # link renders with no marker, so that reason is gone and these are drawn.
  describe "a thick link" do
    ["1==b", "A==b", "A==B"].each do |statement|
      it "refuses #{statement}, which is only two equals" do
        expect(parses?("graph TD\n#{statement}\n")).to be(false)
      end
    end

    { "A===B" => %w[A B], "A====B" => %w[A B], "1===b" => %w[1 b] }
      .each do |statement, ids|
      it "accepts #{statement} and draws it without an arrowhead" do
        source = "graph TD\n#{statement}\n"
        expect(node_ids(source)).to eq(ids)
        expect(described_class.new.parse(source).edges.first.arrow_type)
          .to eq("thick_line")
      end
    end

    {
      "1==>b" => %w[1 b],
      "A==>B" => %w[A B],
      "A===>B" => %w[A B]
    }.each do |statement, ids|
      it "accepts #{statement}" do
        expect(node_ids("graph TD\n#{statement}\n")).to eq(ids)
      end
    end
  end

  # All THREE of mermaid's links carry a trailing marker — the plain one
  # is `[xo<]?--+[-xo>]`, the thick one `[xo<]?==+[=xo>]` and the dotted
  # one `[xo<]?-?\.+-[xo>]?` — so a trailing `x` or `o` belongs to the
  # LINK and `A---x`, `A===x` and `A-.-x` are each one token.
  # mmdc then refuses `A---x --- Z` for holding two links with nothing
  # between them, and this refuses it too — the marker is not drawn,
  # because sirena has no crossed or circled arrowhead and the wrong head
  # would be worse than none. `a thick link` above no longer makes that
  # call for `===`: a headless link now has a type that draws no marker,
  # while a crossed or circled head still has no shape to draw.
  #
  # The thick members are here because `thick_arrow` reached the guard
  # last and shipped without it: `A===xB` drew a node called `xB` that
  # mermaid never puts on the page, and `A===x` `A===o` and `A====x`
  # parsed while mmdc refuses every one. The accept side — `A===B`
  # `A====B` `A==>B` `A===>B` — is pinned in `a thick link` above, so the
  # guard cannot buy these refusals by refusing a headless thick link.
  describe "an arrowhead marker on a link" do
    %w[A---x A-.-x A---o #---x 1-.-o é---x
       A===x A===o A====x 1===o é===x].each do |statement|
      it "refuses #{statement} in front of a second link" do
        expect(parses?("graph TD\n#{statement} --- Z\n")).to be(false)
      end
    end

    # mmdc refuses a bare marker tail too: the link has no target behind
    # it. The shipped `thick_arrow` accepted all four, reading the marker
    # as the target's whole id.
    context "with nothing behind the marker" do
      %w[A===x A===o A====x A=====o].each do |statement|
        it "refuses #{statement}" do
          expect(parses?("graph TD\n#{statement}\n")).to be(false)
        end
      end
    end

    # After `-->` or `-.->` mermaid has already closed the link, so the
    # letter behind it really is a node and both of these draw.
    { "A-->x --- Z" => %w[A Z x], "A-.->x --- Z" => %w[A Z x],
      "A---B --- Z" => %w[A B Z] }.each do |statement, ids|
      it "still reads #{statement} as #{ids.join(', ')}" do
        expect(node_ids("graph TD\n#{statement}\n")).to eq(ids)
      end
    end

    # The under-acceptance the refusal buys: mmdc draws `A---xB` and
    # `A===xB` alike as A to B with a head sirena cannot draw — `x` is a
    # crossed one, `o` a circled one. Pinned so that modelling those
    # heads — the same change that owns `1x-->B` — is a decision rather
    # than an accident. `A===xB` drew `A` and a node called `xB` before
    # the thick link carried the guard. Both markers on every spelling,
    # so an omission cannot hide in the gap.
    context "with a target behind the marker" do
      %w[A---xB A---oB A===xB A===oB A====xB A====oB
         A-.-xB A-.-oB].each do |statement|
        it "refuses #{statement}, whose head mmdc draws and sirena cannot" do
          expect(parses?("graph TD\n#{statement}\n")).to be(false)
        end
      end
    end
  end

  # Reading each edge's SVG `data-id` from mmdc 11.12.0 gave
  # `1x-->B` -> `L_1_B`, `11x-->B` -> `L_11_B`, `1o-->B` -> `L_1_B`,
  # `1x==>B` -> `L_1_B`, `1x-.->B` -> `L_1_B`, `1xx-->B` -> `L_1xx_B`,
  # `1ax-->B` -> `L_1ax_B`, `1_x-->B` -> `L_1_x_B`,
  # `1.x-->B` -> `L_1.x_B`, `a1x-->B` -> `L_a1x_B`, and
  # `ax-->B` -> `L_ax_B`.
  #
  # Sirena models no `x`/`o` arrowheads: `arrow` is only `thick_arrow |
  # dotted_arrow | plain_arrow`. Once an id correctly stops before the
  # marker, nothing can consume `x--` or `o--`, so refusing is correct
  # by omission. The defect guarded against is drawing `1x` or `#x` as a
  # node, which is a different graph from mermaid's. Adding the arrowhead
  # is a separate change.
  #
  # WHERE the id stops is a lexer restart, the same walk every other
  # guard in this grammar runs — not a leading run of digits, which is
  # that walk measured on one prefix shape. mmdc splits `#x-->B` into
  # `#` and `B`, and `&x---B` `*o-.-B` `éx-->B` `中o===B` `#1x-->B`
  # `1#x-->B` `Aéx-->B` and `Zéo==>B` the same way. Over 228 probed
  # sources — 19 prefixes, each with `x` and `o`, against all six link
  # spellings — a digit prefix stopped and nine other restart prefixes
  # did not, drawing a node mermaid never puts on the page in 108 of
  # them.
  #
  # Both directions are pinned, because a guard proven on one side is
  # how this shipped: a settled character in front of the marker means
  # NO restart, so `Zx-->B` and `A#x-->B` stay one node and a link.
  describe "an id before an arrowhead marker" do
    ["1x-->B", "11x-->B", "1o-->B", "1x==>B", "1x-.->B",
     "#x-->B", "&x---B", "*o-.-B", "éx-->B", "中o===B",
     "#1x-->B", "1#x-->B", "Aéx-->B", "Zéo==>B"].each do |statement|
      it "refuses #{statement} after splitting the id at the marker" do
        expect(parses?("graph TD\n#{statement}\n")).to be(false)
      end
    end

    # No restart stands in front of the marker in any of these, so mmdc
    # keeps it in the id. `#`, `&`, `*` and a digit carry a settled run
    # along rather than restarting it, which is why `A#x` differs from
    # `#x` and `A1x` from `1x`.
    {
      "1xx-->B" => ["1xx", "B"],
      "1ax-->B" => ["1ax", "B"],
      "1_x-->B" => ["1_x", "B"],
      "1.x-->B" => ["1.x", "B"],
      "a1x-->B" => ["B", "a1x"],
      "ax-->B" => ["B", "ax"],
      "Zx-->B" => ["B", "Zx"],
      "A#x-->B" => ["A#x", "B"],
      "A&x-->B" => ["A&x", "B"],
      "A*x-->B" => ["A*x", "B"],
      "A1x-->B" => ["A1x", "B"],
      "Zéax-->B" => ["B", "Zéax"]
    }.each do |statement, ids|
      it "keeps the whole id in #{statement}" do
        expect(node_ids("graph TD\n#{statement}\n")).to eq(ids)
      end
    end

    # The marker is only a marker when a link opening ABUTS it. Put a
    # space in front of the link, or leave the link off altogether, and
    # `#x` `éo` and `*o` are ordinary ids — the walk must not refuse them
    # for carrying an `x` or an `o` at a restart. `#x --> B` differs from
    # the refused `#x-->B` by that space alone.
    context "with nothing abutting the marker" do
      {
        "#x --> B" => ["#x", "B"], "éo --> B" => ["B", "éo"],
        "#x" => ["#x"], "*o" => ["*o"]
      }.each do |statement, ids|
        it "still takes #{statement} as #{ids.join(', ')}" do
          expect(node_ids("graph TD\n#{statement}\n")).to eq(ids)
        end
      end
    end
  end

  # The examples below pin `K-->Z` and `1K --> Z`. `K[L]` and `K.foo-->Z`
  # were also measured but are not asserted here. mmdc refuses all four for
  # a reserved word and takes all four for the rest, so the split is the word,
  # not the shape.
  describe "words mermaid lexes as keywords" do
    it "matches the grammar's reserved words" do
      expect(Sirena::Parser::Grammars::Flowchart::RESERVED_WORDS.sort)
        .to eq(self.class.expected_reserved_words.sort)
    end

    expected_reserved_words.each do |word|
      it "refuses #{word} as a node id" do
        expect { described_class.new.parse("graph TD\n#{word}-->Z\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      # A digit run lexes as a number, so the keyword after it has to stand
      # alone. Testing only `1end` passed with a rule that named just it.
      it "refuses 1#{word} as a node id" do
        expect { described_class.new.parse("graph TD\n1#{word} --> Z\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    # These read as keywords elsewhere in mermaid's grammar but not here.
    # `click` in particular was reserved and should not have been.
    %w[click direction accTitle accDescr default href call callback]
      .each do |word|
      it "takes #{word} as an ordinary node id" do
        expect(node_ids("graph TD\n#{word}-->Z\n")).to eq([word, "Z"].sort)
      end
    end

    it "still takes a word that merely starts with a keyword" do
      # `endpoint` starts with one; `aend` only ends with one, which the
      # table above already covers.
      expect(node_ids("graph TD\nendpoints --> Z\n")).to eq(%w[Z endpoints])
    end
  end

  # Three positions, three different vocabularies. Each word below was
  # probed in all three against mmdc: the statement keywords are plain text
  # in a subgraph id, the link-style and click-action words are tokens
  # there, and a click target takes anything at all.
  #
  # Deriving one list from another passed the four cases that had specs and
  # was wrong for eight words that did not.
  #
  # The subgraph body holds a LINK, not a bare node. mermaid opens its
  # click state on `subgraph click [T]` and swallows the title, which a
  # body of `X` alone never notices — the subgraph just comes out
  # anonymous. A link on the next line turns that into the parse error it
  # always was, and it is what moved `click` from A to R here.
  #
  # The first column asks the raw grammar via `subgraph_name_parses?`, while
  # the other two ask the full parser via `parses?`. The asymmetry is needed
  # because `lib/sirena/parser/transforms/flowchart.rb` refuses every
  # subgraph, leaving the grammar as the only layer that can answer the first
  # question.
  describe "the three id positions" do
    {
      "default" => "RAA", "direction" => "AAA", "accTitle" => "AAA",
      "accDescr" => "AAA", "href" => "RAA", "call" => "RAA",
      "callback" => "AAA", "click" => "RAA", "end" => "AAR",
      "graph" => "AAR", "style" => "AAR", "class" => "AAR",
      "classDef" => "AAR", "subgraph" => "AAR", "flowchart" => "AAR",
      "linkStyle" => "AAR", "interpolate" => "RAR", "_self" => "RAR",
      "_blank" => "RAR", "_parent" => "RAR", "_top" => "RAR",
      "swimlane-beta" => "AAR", "plain" => "AAA"
    }.each do |word, expected|
      it "reads #{word} as #{expected} across subgraph, click and node" do
        accepted = [
          subgraph_name_parses?(
            "graph TD\nsubgraph #{word} [Title]\nX --> Y\nend\n"
          ),
          parses?("graph TD\nA-->B\nclick #{word} \"https://example.com\"\n"),
          parses?("graph TD\n#{word}-->Z\n")
        ]

        expect(accepted.map { |value| value ? "A" : "R" }.join).to eq(expected)
      end
    end
  end

  # A quoted id is a subgraph's alone: mmdc refuses `"A"-->Z`,
  # `click "AB" "url"`, `style "A" fill:#f9f` and `class "A" foo`, and
  # renders `subgraph "AB" [Title]`. The style and class targets read
  # through the node rule, so dropping the quote from it moved them too.
  describe "a quoted id" do
    it "names a subgraph" do
      source = "graph TD\nsubgraph \"AB\" [Title]\nX --> Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(true)
    end

    # The shared `quoted_string` takes an empty body; mmdc refuses an empty
    # subgraph name and draws a blank one, so this reads the local
    # `quoted_run` instead, which is never empty.
    it "does not name a subgraph with nothing in it" do
      source = "graph TD\nsubgraph \"\"\nX --> Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(false)
    end

    it "names a subgraph with only a space in it" do
      source = "graph TD\nsubgraph \" \"\nX --> Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(true)
    end

    # An empty pair names nothing alone and still stands in front of a
    # name, with or without a space. Reading only `quoted_run` here refused
    # both of these, which is more than mermaid does.
    ['subgraph "" A', 'subgraph "" x', 'subgraph ""A', 'subgraph ""x']
      .each do |head|
      it "names a subgraph with #{head.inspect}" do
        source = "graph TD\n#{head}\nX --> Y\nend\n"

        expect(subgraph_name_parses?(source)).to be(true)
      end
    end

    # A quoted part anywhere BUT the front is still refused, and so is an
    # empty pair trailed only by spaces. mmdc draws all four. They are one
    # gap with `subgraph A B:C` above — a name here is built from id words
    # and one leading quoted run, where mermaid's is `textNoTags`. Pinned
    # as refusals so that widening the name is a decision, not a drift.
    ['subgraph "" ""', 'subgraph A ""', 'subgraph "AB" ""',
     'subgraph ""  '].each do |head|
      it "does not yet name a subgraph with #{head.inspect}" do
        source = "graph TD\n#{head}\nX --> Y\nend\n"

        expect(subgraph_name_parses?(source)).to be(false)
      end
    end

    # mmdc does not refuse `subgraph "" [T]` — it crashes rendering it
    # ("Cannot read properties of undefined"), so there is no verdict to
    # copy. Refused here, and recorded as unevidenced rather than pinned
    # against mermaid.
    it "does not name a subgraph with an empty pair and a title" do
      source = "graph TD\nsubgraph \"\" [T]\nX --> Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(false)
    end

    it "does not name a node" do
      expect(parses?("graph TD\n\"A\"-->Z\n")).to be(false)
    end

    it "does not name a click target" do
      source = "graph TD\nA-->B\nclick \"AB\" \"https://example.com\"\n"

      expect(parses?(source)).to be(false)
    end

    it "does not name a style target" do
      source = "graph TD\nA-->B\nstyle \"A\" fill:#f9f\n"

      expect(parses?(source)).to be(false)
    end

    it "does not name a class target" do
      expect(parses?("graph TD\nA-->B\nclass \"A\" foo\n")).to be(false)
    end
  end

  # The charset was measured one character at a time. An id runs over
  # printable ASCII, minus the characters that mean something else here,
  # and over letters in the basic plane.
  describe "the id charset" do
    # Both lists hold characters a node id TAKES. They are split by which
    # ones also get a subgraph-name example, not by the expected verdict.
    # The ones below are covered for subgraph names by the `A+B` example
    # at the end of this block, so repeating them per character buys
    # nothing.
    ascii_chars = [
      ["a plus", "A+B"],
      ["an exclamation", "A!B"],
      ["a hash", "A#B"],
      ["a star", "A*B"],
      ["a question mark", "A?B"],
      ["a backslash", "A\\B"]
    ].freeze

    # These get a subgraph-name example too, because a subgraph name is
    # built by its own rule over the same charset. Mostly letters outside
    # ASCII; the quote and the backtick are printable ASCII and sit here
    # rather than above only because they are pinned in both positions.
    subgraph_covered_chars = [
      ["an accent", "café"],
      ["an ideograph", "中文"],
      ["a feminine ordinal", "aªb"],
      ["a micro sign", "aµb"],
      ["a fullwidth A", "aＡb"],
      ["a single quote", "A'B"],
      ["a backtick", "A`B"],
      # Two Mongolian letters mermaid takes and Ruby's \p{L} does not.
      ["a Mongolian A", "A\u1885B"],
      ["a Mongolian I", "A\u1886B"]
    ].freeze

    (ascii_chars + subgraph_covered_chars).each do |label, id|
      it "takes #{label}" do
        expect(node_ids("graph TD\n#{id}-->Z\n")).to eq([id, "Z"].sort)
      end
    end

    subgraph_covered_chars.each do |label, id|
      it "takes #{label} in a subgraph name" do
        source = "graph TD\nsubgraph #{id} [Title]\nX --> Y\nend\n"

        expect(subgraph_name_parses?(source)).to be(true)
      end
    end

    it "takes a widened id as a subgraph name" do
      source = "graph TD\nsubgraph A+B [Title]\nX --> Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(true)
    end
  end

  # mmdc joins these to an id — it draws `A:B`, `A,B`, `A%B` and `A"B` as
  # single nodes — and this grammar deliberately does not, because each one
  # also opens something else here: an inline class, a declaration list, a
  # comment and a quoted label. Pinned so that widening the charset into them
  # is a decision rather than an accident.
  describe "printable ASCII this grammar holds back" do
    { "a colon" => "A:B", "a comma" => "A,B",
      "a percent" => "A%B", "a double quote" => 'A"B' }.each do |label, id|
      it "refuses #{label}, which mmdc draws" do
        expect(parses?("graph TD\n#{id} --- Z\n")).to be(false)
      end
    end
  end

  # Mermaid spells its id charset out, so an id is not "anything that is
  # not punctuation". A negated class took every codepoint the lexer does
  # not, and `😀 --- Z` parsed here while mmdc failed to lex it.
  #
  # Category and plane both matter, and so does the Unicode VERSION. The
  # letters come from mermaid's own table, frozen at 6.1, not from Ruby's
  # newer one. The last two rows are letters Ruby counts and that table
  # does not, so both parsed here while mmdc failed to lex them.
  #
  # A click target obeys none of it — mmdc drew all fourteen of these
  # there. Every row was measured against mmdc 11.12.0 in all three
  # positions.
  describe "characters mermaid keeps out of an id" do
    it "refuses an emoji as a whole node id" do
      expect(parses?("graph TD\n\u{1F600} --- Z\n")).to be(false)
    end

    {
      "an emoji" => "\u{1F600}",
      "an astral letter" => "\u{1D400}",
      "a combining acute" => "\u0301",
      "an arabic-indic digit" => "١",
      "a superscript two" => "²",
      "a braille blank" => "\u2800",
      "a roman numeral" => "Ⅰ",
      "an ideographic zero" => "〇",
      "a NUL" => "\u0000",
      "an ESC" => "\u001B",
      "a DEL" => "\u007F",
      "a C1 control" => "\u0085",
      "a letter added in Unicode 8" => "\u08B3",
      "a letter added in Unicode 9" => "\u1C80"
    }.each do |label, char|
      it "refuses #{label} in a node id" do
        expect(parses?("graph TD\nA#{char}B --- Z\n")).to be(false)
      end

      it "refuses #{label} in a subgraph id" do
        source = "graph TD\nsubgraph A#{char}B [T]\nX --> Y\nend\n"

        expect(subgraph_name_parses?(source)).to be(false)
      end

      it "still takes #{label} in a click target" do
        source = "graph TD\nA --- B\nclick A#{char}B \"https://example.com\"\n"

        expect(parses?(source)).to be(true)
      end
    end
  end

  # The printable ASCII mermaid refuses outright. Nothing here covered it
  # before, so widening the class to take `A@B` passed the whole suite.
  describe "printable ASCII mermaid keeps out of an id" do
    ["(", ")", "<", "=", ">", "@", "[", "]", "^", "{", "|", "}",
     "~"].each do |char|
      it "refuses A#{char}B" do
        expect(parses?("graph TD\nA#{char}B --- Z\n")).to be(false)
      end
    end
  end

  # `click`, `href` and `call` open a directive when whitespace follows or
  # nothing does; tight against the next character they are ordinary ids.
  describe "the directive keywords" do
    %w[click href call].each do |word|
      it "reads #{word} tight against a link as a node" do
        expect(node_ids("graph TD\n#{word}-->Z\n")).to eq([word, "Z"].sort)
      end

      it "refuses a bare #{word}" do
        expect(parses?("graph TD\n#{word}\n")).to be(false)
      end

      # Mermaid appends a newline before it lexes, so the last word in a
      # source is followed by whitespace even when the file is not.
      it "refuses a bare #{word} at the end of the source" do
        expect(parses?("graph TD\n#{word}")).to be(false)
      end

      # A `%%` with a word in front of it is not a comment: mermaid strips
      # one only at the start of a line, so mmdc reads `#{word}%%c` as a
      # single node called `#{word}%%c`. This refuses it, because `%` is
      # not in a node id here — and it used to draw `#{word}` alone, which
      # is neither mmdc's node nor a refusal. The link example above
      # already shows the word is an ordinary id with something tight
      # behind it.
      it "refuses #{word} against a %%, which mmdc reads as one node" do
        expect(parses?("graph TD\n#{word}%%c\n")).to be(false)
      end
    end

    %w[href call].each do |word|
      it "refuses a spaced #{word}" do
        expect(parses?("graph TD\n#{word} --> Z\n")).to be(false)
      end
    end
  end

  # A dot run against a dash opens a dotted link. Against an equals sign it
  # does not, and excluding both refused `.==>B`, which mermaid draws.
  describe "a dot beside a link" do
    it "refuses a dot run that opens a dotted link" do
      expect { described_class.new.parse("graph TD\n.-->B\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    # However long the run is. A rule that read a single dot still refused
    # `.-->B` and then took `..-->B`, which mmdc refuses.
    %w[..-->B ...-->B ..---B ..-.->B].each do |statement|
      it "refuses #{statement}" do
        expect(parses?("graph TD\n#{statement}\n")).to be(false)
      end
    end

    it "takes a two-dot node before a thick link" do
      expect(node_ids("graph TD\n..==>B\n")).to eq(%w[.. B].sort)
    end

    it "takes a two-dot node before a spaced link" do
      expect(node_ids("graph TD\n.. --> B\n")).to eq(%w[.. B].sort)
    end

    it "takes a dot node before a thick link" do
      expect(node_ids("graph TD\n.==>B\n")).to eq(%w[. B].sort)
    end

    it "takes a dot node before a spaced link" do
      expect(node_ids("graph TD\n. --> B\n")).to eq(%w[. B].sort)
    end

    it "still takes a dot inside an ordinary id" do
      expect(node_ids("graph TD\na.b-->c\n")).to eq(%w[a.b c])
    end

    # Anywhere but the front, a dot joins whatever follows it. Guarding
    # the dot against a dash as well refused all five of these, and mmdc
    # draws every one.
    { "A.-->B" => %w[A. B], "A.---B" => %w[A. B],
      "A.-.->B" => %w[A. B], "A..-->B" => %w[A.. B],
      "A.-B --- Z" => ["A.-B", "Z"] }.each do |statement, ids|
      it "reads #{statement} as #{ids.join(' and ')}" do
        expect(node_ids("graph TD\n#{statement}\n")).to eq(ids.sort)
      end
    end

    # `x` and `o` are mermaid's left arrowheads, so a lone one in front of
    # a dotted dash is not an id. The letter appearing is not enough —
    # `X.-` `x1.-` `xx.-` and `xo.-` all draw.
    #
    # Behind a lexer restart the arrowhead opens a link off a real node,
    # so it only fails when nothing follows the dash. Guarding on a digit
    # run alone was wrong both ways: it took `#x.-` and `éx.-`, which mmdc
    # refuses, and refused `1x.-B`, which mmdc draws.
    %w[x.- o.- 1x.- x..- x.-z #x.- &x.- *x.- éx.- 中x.- 1#x.- #1x.-
       Zéx.- aéx.- xéx.- #o.- éo.- #Zéx.- 1Zéx.- #aéo.-].each do |id|
      it "refuses #{id} in front of a link" do
        expect(parses?("graph TD\n#{id} --> Z\n")).to be(false)
      end
    end

    %w[A.- y.- X.- O.- x1.- xx.- xo.- #x.-B 1x.-B 11x.-B éx.-B 中x.-B
       #x.-1 Zéax.-B].each do |id|
      it "takes #{id} in front of a link" do
        expect(node_ids("graph TD\n#{id} --> Z\n")).to eq([id, "Z"].sort)
      end
    end

    # The opening is a link, so mermaid starts a fresh token behind it and
    # a reserved word landing there is a keyword again. The hunt stalled
    # on the `x.-` and never looked past it, so every one of these parsed
    # while mmdc refused it.
    #
    # The last six end their word on an accent, and they are why the hunt
    # has to try the opening FIRST. Reaching for a restart instead runs
    # the settled characters straight through the keyword to the accent
    # and lands behind it, with the word never looked at.
    %w[#x.-end #x.-href #x.-style #x.-class #x.-call #x.-click #x.-graph
       1x.-end éx.-end #o.-end
       #x.-endé #x.-styleé #x.-classé #x.-endéa #o.-endé
       1x.-endé].each do |id|
      it "refuses #{id}, whose keyword sits behind the opening" do
        expect(parses?("graph TD\n#{id} --- Z\n")).to be(false)
      end
    end

    # Mermaid's dotted-link rule is `/^(?:\s*[xo<]?-?\.+-[xo>]?\s*)/`, so
    # the opening carries a marker at BOTH ends. Spelling only its middle
    # read `x.-x` as `x.-` plus a stray `x` and restarted every guard one
    # character early — mmdc refuses all of these and this took them all.
    describe "a marker closing the opening" do
      # `#x.-xend` is the one that shows the damage: the keyword hunt this
      # file is mostly about walked straight past `end`, because the token
      # in front of it had been cut short.
      %w[#x.-x #x.-o #x.-xend 1x.-x #o.-o &x.-x *x.-x éx.-x #x.-x.-B]
        .each do |id|
        it "refuses #{id}, whose link marker is not an id character" do
          expect(parses?("graph TD\n#{id} --- Z\n")).to be(false)
        end
      end

      # A leading dash is part of the same opening (`-?` in the rule
      # above), so `x-.-` is a link where `x1.-` is an id.
      it "refuses x-.-1, whose opening leads with a dash" do
        expect(parses?("graph TD\nx-.-1 --- Z\n")).to be(false)
      end

      # The marker is only a marker. An ordinary letter behind the opening
      # still continues the id, and mmdc draws both of these.
      %w[#x.-B #x.-b].each do |id|
        it "still takes #{id} whole" do
          expect(node_ids("graph TD\n#{id} --- Z\n")).to eq([id, "Z"].sort)
        end
      end
    end

    it "refuses #x.-1.-->B, whose dotted link sits behind the opening" do
      expect(parses?("graph TD\n#x.-1.-->B\n")).to be(false)
    end

    # Two ways the word behind an opening stays plain text, and mmdc
    # draws one node for both. On the first six a settled character in
    # front killed the opening, so there is no fresh token at all. On the
    # rest the opening is real but nothing reserved starts the token.
    %w[Zéax.-end Zaax.-end Zéabx.-end #Zx.-end #ax.-end Zx.-end
       #x.-endx #x.-aend #x.-aendé #x.-endxé #x.-Bé].each do |id|
      it "takes #{id} whole" do
        expect(node_ids("graph TD\n#{id} --- Z\n")).to eq([id, "Z"].sort)
      end
    end
  end

  # Mermaid finds a dotted-link opening wherever its lexer restarts, not
  # only at the front of an id. The places are the same ones the keyword
  # hunt walks, so a buried accent opens one: `Zé.-->B` is a link and
  # `Zéa.-->B` is a node called `Zéa.`. Guarding only the id start took
  # every refusal below.
  #
  # What follows the opening does not change it. mmdc refuses most of
  # these outright, including `1.-` and `1.-x`. The four with a link
  # behind them it does draw, but as three nodes — `1`, `a` and the
  # target — because `.-` opened a dotted link between the first two.
  # Sirena has no `-.-` link to build, so it refuses the line rather
  # than putting up a node called `1.-a` that mermaid never draws.
  describe "where mermaid finds a dotted-link opening" do
    (%w[1.-->B 11.-->B #.-->B &.-->B *.-->B é.-->B 中.-->B Zé.-->B
        aé.-->B Zé1.-->B 1#.-->B #1.-->B xé.-->B 1é.-->B
        #Zé.-->B 1Zé.-->B #aé.-->B éZé.-->B
        1.-==>B 1.---B #.---B 1.----B] +
      ["1.- --- Z", "1.-x --- Z", "1.-a --- Z", "1.-é --- Z",
       "#.-a --- Z"]).each do |statement|
      it "refuses #{statement}" do
        expect(parses?("graph TD\n#{statement}\n")).to be(false)
      end
    end

    # A settled character kills the hunt, so the dot is just a dot.
    { "_.-->B" => %w[_. B], "$.-->B" => %w[$. B], "Z.-->B" => %w[Z. B],
      "a.-->B" => %w[a. B], "Z1.-->B" => %w[Z1. B],
      "Z#.-->B" => %w[Z#. B], "Zéa.-->B" => %w[Zéa. B],
      "a..-->B" => %w[a.. B], "#Zéa.-->B" => %w[#Zéa. B],
      "#Z1.-->B" => %w[#Z1. B] }.each do |statement, ids|
      it "reads #{statement} as #{ids.join(' and ')}" do
        expect(node_ids("graph TD\n#{statement}\n")).to eq(ids.sort)
      end
    end
  end

  # Mermaid does not stop hunting for a keyword at the start of an id, so
  # a reserved word buried in one is still a keyword there. Where it looks
  # again is a position, not a character: `#` `&` `*` and digits carry
  # along whatever came before them, a letter outside ASCII starts the
  # hunt over, and every other id character settles it.
  #
  # Naming only the digit trigger, as the rule did before, passed `1end`
  # and took `#end` `&end` `*end` `éend` `##end` and `Zéend`. mmdc 11.12.0
  # refuses all six.
  #
  # An id can hold more than one of those places and the keyword may sit
  # at any of them, so `#Zéend` is refused and `#ZéAend` is not.
  #
  # A dot and a hyphen settle the hunt like any other id character, which
  # is why `a.end` is an id and `a.éend` is not — there the dot is carried
  # past as plain text and the accent behind it starts the hunt again.
  #
  # Every place has to be checked, not just the last one: `#Zéend.Zéa`
  # holds a keyword at its second place and an id character at its third,
  # so a walk that only looked where it finally stopped took it.
  describe "where mermaid looks for a keyword again" do
    %w[#end &end *end 1end 12end éend 中end ##end 1#end 12#end
       Zéend aéend Zé1end Zé#end ZA中end ªend αend
       1href 12call #click &call *style é_self
       #Zéend 1Zéend éZéend #Zé1end &Aé*end *Zé#style #Zé_self
       a.éend a-éend a.éstyle a-éclass Z.éend
       #Zéend.Zéa #Zéend-Zéa #Zéstyle.Zéa].each do |id|
      it "refuses #{id} as a node id" do
        expect(parses?("graph TD\n#{id} --- Z\n")).to be(false)
      end
    end

    %w[1end_ 1end2 1endx].each do |id|
      it "accepts #{id} at the reserved-word boundary" do
        expect(node_ids("graph TD\n#{id}-->Z\n")).to eq([id, "Z"].sort)
      end
    end

    it "refuses 1endé as a node id" do
      expect(parses?("graph TD\n1endé --- Z\n")).to be(false)
    end

    %w[Z#end Z1end Z##end Z1#end #Z#end 1Z#end ZéAend éA1end Zé_end
       中Aend $end ?end _end +end !end /end -end .end #endx #Zend
       #ZéAend 1ZéAend #Zé_end éZéAend #Aé1endx
       a.end a-end a.éx #ZéendZéa #Zéa.Zéa].each do |id|
      it "takes #{id} whole as a node id" do
        expect(node_ids("graph TD\n#{id} --- Z\n")).to eq([id, "Z"].sort)
      end
    end
  end

  # Every accent starts the hunt over, so this id holds a thousand places
  # to look. Walking them with a rule that called itself blew the Ruby
  # stack, and mmdc draws the id.
  describe "a very long id" do
    let(:id) { "aé" * 1000 }

    it "takes a 2000-character node id without running out of stack" do
      expect(node_ids("graph TD\n#{id} --- Z\n")).to eq([id, "Z"].sort)
    end

    it "takes a 2000-character subgraph name too" do
      source = "graph TD\nsubgraph #{id} [T]\nX --> Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(true)
    end
  end

  # An unbracketed subgraph name runs to the end of the line. Stopping it
  # at the first space left the rest on the line and the body took it as a
  # statement, so `subgraph 1 abc` grew a node called `abc`. mmdc titles
  # that subgraph "1 abc" and draws only X and Y.
  describe "an unbracketed subgraph name with spaces" do
    it "consumes an unbracketed name with spaces to the end of the line" do
      source = "flowchart TD\nsubgraph 1 abc\nX-->Y\nend\n"

      # The guarded-against node cannot be observed here, only the consumption.
      expect(subgraph_name_parses?(source)).to be(true)
    end

    it "still takes a bracketed title" do
      source = "flowchart TD\nsubgraph A [T]\nX-->Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(true)
    end

    # The title sits AFTER the trailing words. A separate arm reading it
    # before them stopped at the first word, so these were refused here
    # while mmdc draws both — and `subgraph A B [T]` was a regression
    # against what this grammar already accepted.
    describe "a bracketed title behind the names" do
      ["subgraph A B [T]", "subgraph A B C [T]"].each do |head|
        it "takes a title after #{head.split.length - 2} names" do
          source = "flowchart TD\n#{head}\nX-->Y\nend\n"

          expect(subgraph_name_parses?(source)).to be(true)
        end
      end

      # Nothing may follow the title. That is pinned once, further down,
      # by "refuses trailing text after a bracketed title".
    end

    # Every trailing word carries the same guards as the first one.
    # Reaching for a bare `id_run` here read the guards off `subgraph_id`,
    # which does not hold them. That let the ten word refusals below parse,
    # plus the bracketed-title case.
    #
    # `end` is the one word that is a keyword HERE and a plain name in the
    # first position, because it closes the subgraph: mmdc draws
    # `subgraph end [T]` and refuses `subgraph A end`.
    %w[interpolate href call click default 1default end 1end .- x.-b]
      .each do |word|
      it "refuses #{word} as a trailing name word" do
        source = "flowchart TD\nsubgraph A #{word}\nX-->Y\nend\n"

        expect(subgraph_name_parses?(source)).to be(false)
      end
    end

    # What closes a subgraph is `end` with the LINE behind it, not the
    # word wherever it stands. Guarding a trailing word on the hunted
    # word alone refused every header below.
    #
    # mmdc 11.12.0 draws each as ONE cluster holding `end` in its name,
    # and WHERE it holds it depends on the title. With a bracketed one
    # the whole run is the cluster id: `subgraph A end [T]` is the
    # cluster `A end` titled `T`, and `A 1end [T]` and `A B end [T]` the
    # same. Without one the cluster is auto-named `subGraph0` and the run
    # becomes its label, so `subgraph A end B` is labelled `A end B`.
    # That was read from mmdc's `class="cluster" id=` and from the text
    # inside its `<foreignObject>` — the oracle's reason for the verdict
    # below, not something these examples measure.
    #
    # What they CAN measure is whether the subgraph is still open, and
    # the example beneath the table does it: drop the closing `end` and
    # the same header must fail. That separates "the name swallowed the
    # word" from "the word closed the subgraph and the rest still
    # parsed", which a bare `parses? == true` cannot tell apart.
    #
    # The refusals above are the other side of the same line:
    # `subgraph A end` and `subgraph A 1end` end their line and mmdc
    # refuses both.
    ["end [T]", "end;", "end ;", "end B", "1end [T]", "end A [T]",
     "B end [T]", "B 1end [T]", "end end [T]"].each do |tail|
      it "takes A #{tail}, whose end does not end the line" do
        source = "flowchart TD\nsubgraph A #{tail}\nX-->Y\nend\n"

        expect(subgraph_name_parses?(source)).to be(true)
      end
    end

    it "reads the title behind a name that swallowed an end" do
      # The discriminator for the table above. A bare `parses? == true`
      # cannot tell "the name swallowed `end` and the title behind it
      # was still read" from "the `end` closed the subgraph and what
      # followed happened to parse anyway". The tree can: a title is
      # captured only on the first reading, because on the second there
      # is no header left to hang one on.
      source = "flowchart TD\nsubgraph A end [T]\nX-->Y\nend\n"

      expect(subgraph_title_of(source)).to eq("[T]")
    end

    # More than one space, both between two names and in front of a
    # bracketed title. mmdc draws all three, and a single-space rule
    # refuses them — every other trailing-name example here uses exactly
    # one space, so the run length went untested.
    ["A  B", "A   B", "A  [T]"].each do |name|
      it "takes #{name.inspect}, whose parts are spaced wide" do
        source = "flowchart TD\nsubgraph #{name}\nX-->Y\nend\n"

        expect(subgraph_name_parses?(source)).to be(true)
      end
    end

    # A statement keyword is plain text in a subgraph name, trailing or
    # not, and mmdc draws all four of these.
    %w[graph style classDef endx].each do |word|
      it "takes #{word} as a trailing name word" do
        source = "flowchart TD\nsubgraph A #{word}\nX-->Y\nend\n"

        expect(subgraph_name_parses?(source)).to be(true)
      end
    end

    # A bracketed title ends the header. Consuming trailing words after it
    # too swallowed the `X` and drew nothing, where mmdc refuses the line.
    it "refuses trailing text after a bracketed title" do
      source = "flowchart TD\nsubgraph A [T] X\nX-->Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(false)
    end

    # mmdc titles this "A B:C". The name charset here is narrower than
    # mermaid's title text, so it is refused instead - the safe direction,
    # and pinned so that widening it stays a decision.
    it "refuses a colon in a trailing name word, which mmdc draws" do
      source = "flowchart TD\nsubgraph A B:C\nX-->Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(false)
    end
  end

  # A subgraph name is hunted the same way with its own six words, plus
  # all three directive words. `end` is a plain name there however the id
  # starts; `click` is NOT, though it took a link-bearing body to see it.
  describe "where mermaid looks again in a subgraph name" do
    # Wraps a bare id into the source `subgraph_name_parses?` wants, so the
    # table below can list ids instead of repeating the diagram each time.
    def names_a_subgraph?(id)
      subgraph_name_parses?(
        "graph TD\nsubgraph #{id} [T]\nX --> Y\nend\n"
      )
    end

    {
      "1default" => false, "##default" => false, "Zédefault" => false,
      "#href" => false, "é_self" => false, "1interpolate" => false,
      "#Zédefault" => false, "1Zéinterpolate" => false,
      "Z#default" => true, "Z1default" => true, "#end" => true,
      "1end" => true, "#Zdefault" => true, "#ZéAdefault" => true,
      # `click` is reserved here like `href` and `call`, and ends a word
      # the same way they do.
      "click" => false, "1click" => false, "#click" => false,
      "éclick" => false, "Zclick" => true, "Z#click" => true,
      "ZéAclick" => true, "clickx" => true, "click1" => true,
      "click." => true, "click_" => true,
      "href-" => true, "call-" => true, "click-" => true,
      # A subgraph's own six reserved words end at a word boundary too,
      # and mmdc draws every name below. Without that boundary each is
      # refused for the reserved word it merely starts with. All six are
      # covered, so dropping one from the list cannot go unnoticed.
      "defaultx" => true, "default_" => true, "interpolatex" => true,
      "_selfx" => true, "_topx" => true, "_blankx" => true,
      "_parentx" => true,
      # Every place gets checked, not just the last one: these hold a
      # reserved word at their second place and an id character at their
      # third, so a walk that only looked where it stopped took them.
      "#Zédefault.Zéa" => false, "#Zéinterpolate.Zéa" => false,
      "#Zé_self.Zéa" => false, "#Zédefault-Zéa" => false,
      "#Zéa.Zéa" => true,
      # A link opening ends a name the same way, and mermaid hunts for it
      # in the same places. Hunting a name for keywords alone took all
      # sixteen refusals below, and mmdc draws none of them.
      #
      # The arrowhead half is stricter here than in a node id: a node may
      # carry on past the opening when something follows it, so `#x.-B`
      # is one node, while `subgraph #x.-b [T]` is refused.
      ".-" => false, ".-a" => false, "x.-" => false, "x.-b" => false,
      "x.-z" => false, "o.-" => false, "1.-" => false, "11.-" => false,
      "#.-" => false, "#x.-" => false, "#x.-b" => false, "éx.-" => false,
      "1x.-b" => false, "Zé.-" => false, "Aé.-b" => false, "...-" => false,
      "a.-" => true, "a.-b" => true, "A.-" => true, "A.-B" => true,
      "Zéa.-" => true, "x1.-" => true, "xx.-" => true, ".." => true,
      "." => true, "A-" => true, "a-b" => true
    }.each do |id, taken|
      it "#{taken ? 'takes' : 'refuses'} #{id} as a subgraph name" do
        expect(names_a_subgraph?(id)).to be(taken)
      end
    end
  end

  # `href`, `call` and `click` end a word differently from the rest. They
  # are keywords only when a space, a tab, a newline or the end of the source
  # follows, so `1href-` and `1hrefé` are ids while `1endé` is not.
  # A comment is NOT one of the endings — see `spaced_keyword`.
  describe "how a keyword ends" do
    %w[1href- 1href. 1hrefé #click- &call- 1click_ éhref#].each do |id|
      it "takes #{id} as a node id" do
        expect(node_ids("graph TD\n#{id} --- Z\n")).to eq([id, "Z"].sort)
      end
    end

    %w[1endé 1style. #class- é_selfé 1interpolate-].each do |id|
      it "refuses #{id} as a node id" do
        expect(parses?("graph TD\n#{id} --- Z\n")).to be(false)
      end
    end
  end

  # `line_end` opens with an optional semicolon, so guarding the directive
  # words on it read `href;` as a directive and refused a line mmdc draws.
  describe "a directive word against a semicolon" do
    %w[click href call].each do |word|
      it "takes #{word}; as a node" do
        expect(parses?("graph TD\n#{word};\n")).to be(true)
      end

      it "takes #{word}; at the end of a chain" do
        expect(parses?("graph TD\nP --- #{word};\n")).to be(true)
      end
    end

    it "still takes 1href; as a node" do
      expect(parses?("graph TD\n1href;\n")).to be(true)
    end
  end

  # A click target is whatever runs up to the next space, tab or newline.
  # mermaid is in its click state there and takes characters no node id may
  # hold, so reusing the node guards refused targets mmdc draws.
  describe "a click target" do
    def click_parses?(line)
      parses?("graph TD\nA-->B\n#{line}\n")
    end

    ["A--B", "A.-B", "-->", "A[B]", "A|B", "A:B", "A\"B", "A;", "A~B",
     "A@B", "A{B}", "A=B", "A,B", "A<B>"].each do |target|
      it "takes #{target} as a target" do
        expect(click_parses?("click #{target} \"https://example.com\""))
          .to be(true)
      end
    end

    it "takes A+B as a target" do
      source = "graph TD\nA-->B\nclick A+B \"https://example.com\"\n"

      expect(parses?(source)).to be(true)
    end

    # Ruby's `\s` holds these two and this grammar's whitespace does not.
    # mmdc draws both, so the target runs straight through them.
    { "a vertical tab" => "A\vB", "a form feed" => "A\fB" }
      .each do |label, target|
      it "runs a target through #{label}" do
        line = "click #{target} \"https://example.com\""

        expect(click_parses?(line)).to be(true)
      end
    end

    it "takes a tab between the target and the action" do
      expect(click_parses?("click A\t\"https://example.com\"")).to be(true)
    end

    # The gap after the keyword is a run, not a single space: mermaid
    # opens its click state on `"click"\s+`.
    { "two spaces after the keyword" => "click  A",
      "three spaces after the keyword" => "click   A",
      "a tab after the keyword" => "click\tA" }.each do |label, head|
      it "takes #{label}" do
        expect(click_parses?("#{head} \"https://example.com\"")).to be(true)
      end
    end

    # The action is not optional, and exactly one space or tab holds it
    # off the target.
    { "a bare target" => "click A",
      "a target and a semicolon" => "click A;",
      "a target and a link" => "click A--B",
      "a target and a trailing space" => "click A ",
      "a target and a trailing tab" => "click A\t",
      "two spaces before the action" => "click A  \"https://example.com\"" }
      .each do |label, line|
      it "refuses #{label}" do
        expect(click_parses?(line)).to be(false)
      end
    end
  end

  # mermaid wants the shape opener hard against the id. Widening the ids
  # brought four more kinds of name to a `ws?` that had been taking a
  # space, a tab, a newline and a whole comment line between the two.
  describe "a gap before a shape opening" do
    gaps = { "a space" => " ", "two spaces" => "  ", "a tab" => "\t",
             "a newline" => "\n", "a comment line" => " %% c\n" }.freeze

    %w[A A1 1 12 é a.b].each do |id|
      it "takes #{id}[B] with the opening against the id" do
        expect(parses?("graph TD\n#{id}[B]\n")).to be(true)
      end

      gaps.each do |label, gap|
        it "refuses #{id}[B] behind #{label}" do
          expect(parses?("graph TD\n#{id}#{gap}[B]\n")).to be(false)
        end
      end
    end

    # The other thirteen of `node_shape`'s fourteen openings. The square
    # one is pinned against every id above.
    ["(B)", "{B}", "((B))", "[[B]]", "[(B)]", ">B]", "([B])", "{{B}}",
     "(((B)))", "[/B/]", "[\\B\\]", "[/B\\]", "[\\B/]"].each do |shape|
      it "refuses 1 #{shape} behind a space" do
        expect(parses?("graph TD\n1 #{shape}\n")).to be(false)
      end
    end

    # Both ends of a link reach the same rule.
    it "refuses a gap on the far side of a link" do
      expect(parses?("graph TD\nZ-->1 [B]\n")).to be(false)
    end

    it "refuses a gap on the near side of a link" do
      expect(parses?("graph TD\n1 [B]-->Z\n")).to be(false)
    end
  end

  # Before mermaid lexes anything it rewrites every `#\w+;` in the source
  # into a placeholder for an HTML entity, and the placeholder is spelt in
  # characters no id may hold. So an id cannot carry the sequence, and the
  # boundary is exact on both sides: the run is `[A-Za-z0-9_]` and the `;`
  # abuts it.
  describe "an entity escape inside an id" do
    { "a letter run" => "#a;B",
      "a longer letter run" => "#ab;B",
      "a digit run" => "#35;B",
      "a mixed run" => "#a1;B",
      "an underscore in the run" => "#x_;B",
      "a bare underscore run" => "#_;B",
      "a named entity" => "#quot;B",
      "an id in front of it" => "A#a;B",
      "a digit in front of it" => "1#a;B",
      "a second hash in front of it" => "##a;B",
      "a hash inside the run" => "#a#b;B",
      "a doubled semicolon after it" => "#a;;B",
      "one behind a separator" => "A-->B;#a;C" }.each do |label, line|
      it "refuses #{label}" do
        expect(parses?("graph TD\n#{line}\n")).to be(false)
      end
    end

    # None of these is `#\w+;`, and mmdc draws every one.
    { "an empty run" => "#;B",
      "an empty run after a digit" => "1#;B",
      "a space before the semicolon" => "#a ;B",
      "no semicolon at all" => "#a\nB",
      "a letter outside ASCII in the run" => "#é;B",
      "a dot in the run" => "#a.b;B",
      "a hyphen in the run" => "#a-b;B" }.each do |label, line|
      it "takes #{label}" do
        expect(parses?("graph TD\n#{line}\n")).to be(true)
      end
    end

    it "refuses one in a subgraph name" do
      source = "graph TD\nZ-->A\nsubgraph #ab_c;\nX-->Y\nend\n"

      expect(subgraph_name_parses?(source)).to be(false)
    end
  end

  # mermaid lexes `end\b\s*` as the token that closes a subgraph, so a
  # name that hunts one up and then ends the line closes the subgraph
  # instead of opening it. It is the same hunt the trailing words run, and
  # it restarts in the same places.
  describe "a subgraph name that hunts up an end" do
    def bare_subgraph_parses?(name)
      subgraph_name_parses?("graph TD\nsubgraph #{name}\nX-->Y\nend\n")
    end

    # Bare names whose hunt lands on `end`. Trailing whitespace does not
    # save them, in any mixture: mermaid's own token is `end\b\s*`, so
    # the run goes with the word.
    ["end", '""end', "1end", "éend", "##end", "1#end", "Zéend", "ZA中end",
     "end ", "end   ", "end\t", "end\t\t", "end \t", "end\t ",
     "end\u00A0", "1end\u00A0"].each do |name|
      it "refuses #{name.inspect} as a whole line" do
        expect(bare_subgraph_parses?(name)).to be(false)
      end
    end

    # Names whose hunt never reaches an `end`, and names that do carry one
    # but are followed by something that is not whitespace — a title,
    # another word or a `;`. That calls the guard off, which is what mmdc
    # does.
    ["Z#end", "Z1end", "ZéAend", "$end", "_end", "Zend", "endx", "end_",
     "end2", "end [T]", "end A", "end A [T]", "end;", "end ;", "end\t;",
     "end\u00A0;", "endx\u00A0", "A\u00A0",
     '""end [T]', '"" end A'].each do |name|
      it "takes #{name.inspect} as a whole line" do
        expect(bare_subgraph_parses?(name)).to be(true)
      end
    end
  end

  # The same space in front of a `;` that node statements already tolerate
  # in `loose_separator`, over the whole space set mermaid reads.
  describe "a space before a subgraph's semicolon" do
    gaps = { "a space" => " ", "a tab" => "\t",
             "a no-break space" => "\u00A0" }.freeze

    %w[A endx end 1end].each do |name|
      gaps.each do |label, gap|
        it "takes #{name} with #{label} before the semicolon" do
          source = "graph TD\nsubgraph #{name}#{gap};\nX-->Y\nend\n"

          expect(subgraph_name_parses?(source)).to be(true)
        end
      end
    end

    # A control: the looser line end must not let anything else past the
    # title. mmdc refuses this, and so did the tighter one.
    it "still refuses a word after a title" do
      source = "graph TD\nsubgraph A [T] X\nY-->Z\nend\n"

      expect(subgraph_name_parses?(source)).to be(false)
    end
  end
end
