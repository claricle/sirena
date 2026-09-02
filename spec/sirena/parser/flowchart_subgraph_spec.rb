# frozen_string_literal: true

require "benchmark"
require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  def node_ids(source)
    described_class.new.parse(source).nodes.map(&:id).sort
  end

  def boxes(source)
    described_class.new.parse(source).subgraphs
  end

  def parses?(source)
    described_class.new.parse(source)
    true
  rescue Sirena::Parser::ParseError
    false
  end

  describe "a subgraph" do
    # `end` is a valid node id, so an unguarded statement list consumed the
    # subgraph's own terminator as a node and the closing `end` never
    # matched. Every subgraph form failed because of it, not just the
    # awkward ones.
    it "parses at all" do
      expect(node_ids("graph TD\nsubgraph s\nA-->B\nend\n")).to eq(%w[A B])
    end

    # Two levels passed with a parser capped at one. The chain, not just
    # the nodes: with `parent_id` never set the three boxes land flat at
    # the top level and every node id still reads the same.
    it "nests three deep" do
      source = "graph TD\nsubgraph a\nsubgraph b\nsubgraph c\n" \
               "A-->B\nend\nend\nend\n"

      expect(boxes(source).map { |box| [box.id, box.parent_id] })
        .to eq([["a", nil], %w[b a], %w[c b]])
      expect(node_ids(source)).to eq(%w[A B])
    end

    # `end` closes a box only as a whole word. Under a bare `str("end")`
    # each of these is refused instead, and nothing in the suite noticed.
    {
      "subgraph endpoint" => %w[endpoint endpoint],
      "subgraph ending [T]" => %w[ending T],
      "subgraph end_x" => %w[end_x end_x]
    }.each do |header, (id, title)|
      it "reads `#{header}` as a box, not a terminator" do
        box = boxes("graph TD\n#{header}\nX\nend\n").first

        expect([box.id, box.title]).to eq([id, title])
      end
    end

    it "lets statements follow the end" do
      source = "graph TD\nsubgraph s\nA\nend\nB-->C\n"

      expect(node_ids(source)).to eq(%w[A B C])
    end

    it "takes a title" do
      expect(parses?("graph TD\nsubgraph s [Title]\nA\nend\n")).to be(true)
    end

    it "still requires the end" do
      # mmdc rejects an unterminated subgraph and so do we.
      expect(parses?("graph TD\nsubgraph s\nA-->B\n")).to be(false)
    end
  end

  describe "a node whose name begins with end" do
    # The boundary is "no identifier character follows", not "a space
    # follows". Testing only `endpoint` passed with either rule.
    %w[endpoint end2 end_node].each do |id|
      it "treats #{id} as a node, not a terminator" do
        source = "graph TD\nsubgraph s\n#{id}-->B\nend\n"

        expect(node_ids(source)).to eq(["B", id].sort)
      end
    end
  end

  describe "what may follow the terminator" do
    # An LF-only rule passed every earlier example.
    {
      "a newline" => "graph TD\nsubgraph s\nA\nend\n",
      "end of input" => "graph TD\nsubgraph s\nA\nend",
      "a semicolon" => "graph TD\nsubgraph s\nA\nend;\n",
      "trailing spaces" => "graph TD\nsubgraph s\nA\nend  \n",
      "tabs around the semicolon" => "graph TD\nsubgraph s\nA\nend\t;\t\r\n",
      "CRLF" => "graph TD\r\nsubgraph s\r\nA\r\nend\r\n"
    }.each do |label, source|
      it "closes on #{label}" do
        expect(parses?(source)).to be(true)
      end
    end
  end

  # The declaration owns the rest of its line, and mermaid takes that rest
  # as the title when it is not bracketed. Reading it as statements made
  # `subgraph s end;A` close the subgraph on its own declaration line.
  describe "the declaration line" do
    it "takes the rest of the line as a title" do
      source = "graph TD\nsubgraph s Some Title\nA\nend\n"

      expect(node_ids(source)).to eq(%w[A])
    end

    it "takes a comment as title text, which is what mermaid does" do
      expect(parses?("graph TD\nA\nsubgraph s %% note\nB\nend\n"))
        .to be(true)
    end

    it "refuses a comment after a bracketed title" do
      expect(parses?("graph TD\nA\nsubgraph s [Title] %% note\nB\nend\n"))
        .to be(false)
    end

    it "refuses anything else after a bracketed title" do
      expect(parses?("graph TD\nsubgraph s [Title] A\nend\n")).to be(false)
    end

    it "does not let end close the subgraph on its own line" do
      # `end` here is the title, so the diagram never closes.
      expect(parses?("graph TD\nsubgraph s end;A\n")).to be(false)
    end

    it "ends at a semicolon, with the body following it" do
      expect(node_ids("graph TD\nsubgraph s;A\nend\n")).to eq(%w[A])
    end

    it "ends at a semicolon after a bracketed title too" do
      expect(node_ids("graph TD\nsubgraph s [Title];A\nend\n")).to eq(%w[A])
    end
  end

  # A title carrying a run of spaces parsed in quadratic time: the old rule
  # re-ran its terminator test at every byte, and each test rescanned the
  # whole run. 4k spaces took 3.7 seconds on a source mmdc renders.
  describe "a long title" do
    it "parses in linear time" do
      source = "graph TD\nsubgraph s #{' ' * 8000}Title\nA\nend\n"

      elapsed = Benchmark.realtime { described_class.new.parse(source) }

      expect(elapsed).to be < 1.0
    end
  end

  # mermaid refuses its own structural characters inside a free title.
  describe "what a free title may contain" do
    {
      "parentheses" => "graph TD\nsubgraph s Title (More)\nA\nend\n",
      "angle brackets" => "graph TD\nsubgraph s Title <More>\nA\nend\n",
      "braces" => "graph TD\nsubgraph s Title {More}\nA\nend\n",
      "an empty bracket title" => "graph TD\nsubgraph s []\nA\nend\n"
    }.each do |label, source|
      it "refuses #{label}" do
        expect(parses?(source)).to be(false)
      end
    end

    it "takes a run of spaces inside it" do
      expect(node_ids("graph TD\nsubgraph s    Title\nA\nend\n")).to eq(%w[A])
    end

    it "takes trailing spaces after it" do
      expect(node_ids("graph TD\nsubgraph s Title   \nA\nend\n")).to eq(%w[A])
    end

    it "still names a subgraph end with a free title" do
      expect(parses?("graph TD\nsubgraph end Some Title\nA\nend\n")).to be(true)
    end
  end

  describe "where the declaration ends" do
    it "refuses a space after a bracketed title" do
      # Consuming one space let `subgraph s  [Title] A` past the bracket
      # guard, and a trailing space before the newline was accepted too.
      expect(parses?("graph TD\nsubgraph s [Title] \nA\nend\n")).to be(false)
    end

    it "refuses a bracketed title with a statement behind it" do
      expect(parses?("graph TD\nsubgraph s  [Title] A\nend\n")).to be(false)
    end

    it "takes a doubled semicolon" do
      expect(node_ids("graph TD\nsubgraph s;;A\nend\n")).to eq(%w[A])
    end

    it "refuses a comment after the semicolon" do
      expect(parses?("graph TD\nsubgraph s; %% note\nA\nend\n")).to be(false)
    end
  end

  # mmdc refuses these with "Setting s as parent of s would create a
  # cycle". The transform discarded the subgraph id, so the cycle was
  # rendered instead of refused.
  describe "a subgraph containing itself" do
    it "is refused" do
      expect(parses?("graph TD\nsubgraph s\ns\nend\n")).to be(false)
    end

    it "is refused when a nested subgraph reuses the id" do
      source = "graph TD\nsubgraph s\nsubgraph s\nA\nend\nend\n"

      expect(parses?(source)).to be(false)
    end

    # Writing the id again is writing the box again, not a node beside
    # it. mmdc 11.12.0 draws cluster `s` and node `A`, and nothing else.
    it "draws no node for the id outside the subgraph" do
      expect(node_ids("graph TD\nsubgraph s\nA\nend\ns\n")).to eq(%w[A])
    end
  end

  # An ancestor chain only sees cycles that nest. Two declarations can
  # close a loop between them, and mermaid refuses that too.
  describe "a containment cycle across declarations" do
    it "refuses two subgraphs holding each other" do
      source = "graph TD\nsubgraph a\nb\nend\nsubgraph b\na\nend\n"

      expect(parses?(source)).to be(false)
    end

    it "refuses a three-way loop" do
      source = "graph TD\nsubgraph a\nb\nend\nsubgraph b\nc\nend\n" \
               "subgraph c\na\nend\n"

      expect(parses?(source)).to be(false)
    end

    # Both ends, not one box named twice. mmdc 11.12.0 reports this exact
    # source as "Setting b as parent of a would create a cycle", and the
    # comment in the transform has quoted that form all along while the
    # code said "a as parent of a".
    it "names both boxes in the loop" do
      source = "graph TD\nsubgraph a\nb\nend\nsubgraph b\na\nend\n"

      expect { described_class.new.parse(source) }
        .to raise_error(Sirena::Parser::ParseError,
                        /Setting b as parent of a would create a cycle/)
    end

    it "still takes a chain that does not close" do
      source = "graph TD\nsubgraph a\nb\nend\nsubgraph b\nX\nend\n"

      expect(parses?(source)).to be(true)
    end

    # Parsing is not the point: mmdc nests box `b` inside `a` and draws
    # no node `b`, and the containment check already reads this chain as
    # `a` holding `b`. The model used to disagree with its own validation
    # and draw two sibling boxes plus a phantom node.
    it "nests the box the chain names" do
      source = "graph TD\nsubgraph a\nb\nend\nsubgraph b\nX\nend\n"
      diagram = described_class.new.parse(source)
      held = diagram.subgraphs.to_h { |box| [box.id, box] }

      expect(diagram.nodes.map(&:id)).to eq(%w[X])
      expect(held["b"].parent_id).to eq("a")
      expect(held["a"].child_ids).to eq(%w[b])
      expect(held["a"].node_ids).to be_empty
    end
  end

  # A subgraph declared with a FREE title gets a generated `subGraph<n>`,
  # so its written word is not its id. Reading the word as the id refused
  # a diagram mmdc renders and accepted the cycle mmdc refuses.
  describe "a generated subgraph id" do
    it "lets the written word appear inside a free-titled subgraph" do
      expect(parses?("graph TD\nsubgraph s Some Title\ns\nend\n")).to be(true)
    end

    it "refuses the generated id inside it" do
      source = "graph TD\nsubgraph s Some Title\nsubGraph0\nend\n"

      expect(parses?(source)).to be(false)
    end

    it "keeps the written id when the title is bracketed" do
      expect(parses?("graph TD\nsubgraph s [Title]\ns\nend\n")).to be(false)
    end

    it "sees through a quoted id" do
      # `{string: "s"}.to_s` is not `s`, so this cycle slipped through.
      expect(parses?("graph TD\nsubgraph \"s\" [Title]\ns\nend\n")).to be(false)
    end
  end

  # mmdc renders 220 nested subgraphs and we refuse them. Refusing is a
  # gap; letting a StackError out of a parse is a crash in the caller.
  describe "a diagram nested past the stack" do
    it "is refused rather than crashing" do
      nested = (0...220).map { |i| "subgraph s#{i}\n" }.join
      source = "graph TD\n#{nested}A\n#{"end\n" * 220}"

      expect { described_class.new.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, /nests too deeply/)
    end
  end

  # A box holds everything below it, not just its own line, so the
  # containment graph is a transitive closure. Walking it with a
  # path-local visited list re-entered every box once per route into it,
  # and the cost doubled per box: 22 took 8 seconds, 24 took fifty, and
  # the 220 mmdc draws would never have come back.
  describe "a deeply nested diagram" do
    it "checks for a cycle without re-walking every route" do
      nested = (0...22).map { |i| "subgraph s#{i}\n" }.join
      source = "graph TD\n#{nested}A-->B\n#{"end\n" * 22}"

      elapsed = Benchmark.realtime { described_class.new.parse(source) }

      expect(elapsed).to be < 1.0
    end
  end

  # Every case here is refused by mmdc 11.12.0, and every one of them used
  # to come back as a drawn cluster. Drawing a box mermaid will not draw is
  # worse than refusing one it draws, so these are the shape of bug this
  # whole change exists to avoid.
  describe "sources mermaid refuses" do
    # Containment was assigned per id rather than merged, so redeclaring a
    # box erased the loop its first declaration had already closed.
    it "still sees a loop after the box is declared again" do
      source = "graph TD\nsubgraph a\nb\nend\n" \
               "subgraph b\na\nend\nsubgraph a\nend\n"

      expect(parses?(source)).to be(false)
    end

    # These two refuse in the GRAMMAR, not in the containment walk. A
    # quoted string is not a statement, so `subgraph a / "a" / end` dies
    # on `Expected "end", but got "\"a\""` and never reaches a cycle
    # check at all. Naming them after the walk would claim cover the
    # walk does not have here — the unquoted forms above are what
    # exercise it, and mutating `reject_containment_cycles` kills those.
    #
    # They are kept because the shape once mattered: a quoted id arrives
    # as a Parslet hash, so `to_s` gave `{string: "a"@21}` and never
    # equalled the id it names. The grammar closing the door first is
    # what makes that unreachable, and this pins the door shut.
    it "refuses a quoted node standing in for a statement" do
      expect(parses?("graph TD\nsubgraph a\n\"a\"\nend\n")).to be(false)
    end

    it "refuses a quoted node inside a second box" do
      source = "graph TD\nsubgraph a\n\"b\"\nend\nsubgraph b\na\nend\n"

      expect(parses?(source)).to be(false)
    end

    # An empty capture is an empty array, not an empty string, so the box
    # came out named `[]` and titled `[]`.
    it "refuses an empty quoted id" do
      expect(parses?("graph TD\nsubgraph \"\"\nA\nend\n")).to be(false)
    end

    it "refuses an empty quoted id with a title" do
      expect(parses?("graph TD\nsubgraph \"\" [T]\nA\nend\n")).to be(false)
    end
  end

  # Claiming a member went through the model's collection setter once per
  # node, which copies the whole array every time. Measured against the
  # same nodes at the top level, because that is the same parse without
  # the claiming — the machine cancels out and the quadratic term does
  # not. The ratio was 3.6 before and sits under 1 now.
  describe "a subgraph holding many nodes" do
    it "costs no more than the same nodes outside one" do
      body = (0...1600).map { |i| "n#{i}" }.join("\n")
      loose = Benchmark.realtime { described_class.new.parse("graph TD\n#{body}\n") }
      boxed = Benchmark.realtime do
        described_class.new.parse("graph TD\nsubgraph s [T]\n#{body}\nend\n")
      end

      expect(boxed).to be < loose * 2
    end
  end

  # mermaid refuses its own structural tokens in a free title.
  describe "more characters a free title may not contain" do
    ["T,X", "T=X", "T@X", "T|X", "T~X"].each do |title|
      it "refuses #{title}" do
        expect(parses?("graph TD\nsubgraph s #{title}\nA\nend\n")).to be(false)
      end
    end

    it "takes a bracketed title straight against the id" do
      expect(node_ids("graph TD\nsubgraph s[Title]\nA\nend\n")).to eq(%w[A])
    end
  end

  # Whitespace alone separates `end` from the next statement.
  describe "a statement straight after the terminator" do
    it "may be separated by a space" do
      expect(node_ids("graph TD\nsubgraph s\nA\nend B-->C\n")).to eq(%w[A B C])
    end

    it "may be separated by a tab" do
      expect(node_ids("graph TD\nsubgraph s\nA\nend\tB-->C\n")).to eq(%w[A B C])
    end

    it "may be separated by more than one space" do
      # Consuming a single space left `end  %% note` accepted and
      # `end  ; B --- C` refused, both the wrong way round.
      expect(node_ids("graph TD\nsubgraph s\nA\nend  ; B --- C\n"))
        .to eq(%w[A B C])
      expect(parses?("graph TD\nsubgraph s\nA\nend  %% note\n")).to be(false)
    end

    it "still refuses a comment there" do
      expect(parses?("graph TD\nsubgraph s\nA\nend %% note\n")).to be(false)
    end
  end

  # The semicolon is a statement separator, so it does not have to be the
  # last thing on the line. Requiring a newline after it refused three
  # forms mmdc renders.
  describe "a semicolon after the terminator" do
    it "lets the next statement share the line" do
      source = "graph TD\nsubgraph s\nA\nend; B-->C\n"

      expect(node_ids(source)).to eq(%w[A B C])
    end

    it "may be doubled" do
      expect(parses?("graph TD\nsubgraph s\nA\nend;;\n")).to be(true)
    end

    it "may close an outer subgraph on the same line" do
      source = "graph TD\nsubgraph a\nsubgraph b\nX\nend;end\n"

      expect(node_ids(source)).to eq(%w[X])
    end
  end

  describe "forms mermaid refuses" do
    {
      "a labelled end" => "graph TD\nsubgraph s\nend[Label]\nend\n",
      "a doubled end" => "graph TD\nsubgraph s\nA\nend\nend\n",
      "a comment on the closing line" =>
        "graph TD\nsubgraph s\nA\nend %% note\n",
      "a comment after the closing semicolon" =>
        "graph TD\nsubgraph s\nA\nend; %% note\n"
    }.each do |label, source|
      it "rejects #{label}" do
        expect(parses?(source)).to be(false)
      end
    end

    it "still takes a comment on the next line" do
      expect(parses?("graph TD\nsubgraph s\nA\nend\n%% note\n")).to be(true)
    end
  end

  # Guarding statement starts left `end` reachable as an edge target and as
  # a style or class target, so `A-->end` built a node mmdc refuses.
  describe "end where a node is referenced" do
    {
      "an edge target" => "graph TD\nA-->end\n",
      "an edge source" => "graph TD\nend-->A\n",
      "a style target" => "graph TD\nA-->B\nstyle end fill:#f9f\n",
      "a class target" => "graph TD\nA-->B\nclass end foo\n"
    }.each do |label, source|
      it "rejects #{label}" do
        expect(parses?(source)).to be(false)
      end
    end

    # mmdc renders both of these, so the keyword is refused where a node is
    # built, not everywhere the word appears.
    it "still names a subgraph, given a title to disambiguate it" do
      # mmdc draws `subgraph end [Title]` and refuses the bare form with an
      # empty body or a nested subgraph inside it. We ask for the title in
      # every case: that costs one form mermaid draws and never claims one
      # it refuses.
      expect(parses?("graph TD\nsubgraph end [Title]\nA\nend\n")).to be(true)
      expect(parses?("graph TD\nsubgraph end\nend\n")).to be(false)
    end

    # Refusing `end` in these positions is only right if an ordinary name
    # still works. Deleting the style and class branches, or narrowing the
    # click guard to the literal keyword, left the suite green.
    {
      "a style target" => "graph TD\nA-->B\nstyle A fill:#f9f\n",
      "a class target" => "graph TD\nA-->B\nclass A foo\n",
      "a click target" => "graph TD\nA-->B\nclick A \"http://example.com\"\n",
      "an edge target" => "graph TD\nA-->B\n"
    }.each do |label, source|
      it "still takes an ordinary name as #{label}" do
        expect(parses?(source)).to be(true)
      end
    end

    it "still names a click target" do
      source = "graph TD\nA-->B\nclick end \"http://example.com\"\n"

      expect(parses?(source)).to be(true)
    end

    it "still takes a target that only starts with end" do
      expect(node_ids("graph TD\nA-->endpoint\n")).to eq(%w[A endpoint])
    end
  end

  describe "the subgraph model" do
    def only(source)
      boxes(source).first
    end

    # Every title case below was read off mmdc 11.12.0.
    it "falls back to the id when nothing is written" do
      expect(only("graph TD\nsubgraph s\nA\nend\n").title).to eq("s")
    end

    it "takes a bracketed title" do
      expect(only("graph TD\nsubgraph s [Title]\nA\nend\n").title)
        .to eq("Title")
    end

    # The word that looks like an id is part of a free title, and mermaid
    # generates the id separately. Reading it as the id labelled the box
    # "s" where mmdc writes "s Some Title".
    it "keeps the leading word in a free title" do
      box = only("graph TD\nsubgraph s Some Title\nA\nend\n")

      expect(box.title).to eq("s Some Title")
      expect(box.id).to eq("subGraph0")
    end

    # The grammar consumed this gap without capturing it, so a run of
    # spaces collapsed to one and the label misquoted the source.
    it "keeps the gap inside a free title" do
      expect(only("graph TD\nsubgraph s  Title\nA\nend\n").title)
        .to eq("s  Title")
    end

    it "keeps a tab inside a free title" do
      expect(only("graph TD\nsubgraph s\tTitle\nA\nend\n").title)
        .to eq("s\tTitle")
    end

    it "claims a node written on its own line" do
      expect(only("graph TD\nsubgraph s\nA\nend\n").node_ids).to eq(%w[A])
    end

    # Both ends of an edge count. Claiming only the statement's first node
    # left B outside the box mermaid draws it in.
    it "claims both ends of an edge inside it" do
      expect(only("graph TD\nsubgraph s\nA-->B\nend\n").node_ids)
        .to eq(%w[A B])
    end

    it "leaves a node declared outside it alone" do
      expect(only("graph TD\nsubgraph s\nA\nend\nB\n").node_ids)
        .to eq(%w[A])
    end

    it "claims a node once however often it is named" do
      expect(only("graph TD\nsubgraph s\nA-->B\nB-->A\nend\n").node_ids)
        .to eq(%w[A B])
    end

    it "records nesting by parent rather than by containment" do
      found = boxes("graph TD\nsubgraph a\nsubgraph b\nA\nend\nend\n")

      expect(found.map(&:id)).to eq(%w[a b])
      expect(found.map(&:parent_id)).to eq([nil, "a"])
      expect(found.map(&:child_ids)).to eq([%w[b], []])
      expect(found.map(&:node_ids)).to eq([[], %w[A]])
    end

    it "keeps siblings apart" do
      found = boxes("graph TD\nsubgraph a\nX\nend\nsubgraph b\nY\nend\n")

      expect(found.map(&:node_ids)).to eq([%w[X], %w[Y]])
      expect(found.map(&:parent_id)).to eq([nil, nil])
    end

    # First box to name a node keeps it. All four measured on mmdc 11.12.0.
    it "leaves a node to the box that named it first" do
      found = boxes("graph TD\nsubgraph a\nx\nend\nsubgraph b\nx\nend\n")

      expect(found.map(&:node_ids)).to eq([%w[x], []])
      expect(found.map(&:drawable?)).to eq([true, false])
    end

    it "still fills a second box from nodes nobody claimed" do
      found = boxes("graph TD\nsubgraph a\nx\nend\nsubgraph b\ny\nend\n")

      expect(found.map(&:node_ids)).to eq([%w[x], %w[y]])
    end

    # Not an id collision rule: mmdc draws both boxes, because `c` was
    # free to claim. `b` inside `a` names the box, so `a` holds the box
    # rather than a node — and both are still drawn.
    it "draws a box whose id is also written inside another" do
      found = boxes("graph TD\nsubgraph a\nb\nend\nsubgraph b\nc\nend\n")

      expect(found.map(&:drawable?)).to eq([true, true])
      expect(found.map(&:node_ids)).to eq([[], %w[c]])
      expect(found.map(&:child_ids)).to eq([%w[b], []])
    end

    # The corpus case that found this: two boxes named `inner` inside one
    # parent. mermaid draws a single `inner`.
    it "merges two boxes sharing an id" do
      found = boxes("graph TD\nsubgraph s\nx\nend\nsubgraph s\ny\nend\n")

      expect(found.map(&:node_ids)).to eq([%w[x y], []])
    end

    # A quoted id arrives from the grammar as a Hash, so comparing the
    # raw capture gave `{string: "a"}` and never matched. mmdc refuses
    # this source outright; we drew two boxes both called "a".
    it "refuses a quoted subgraph nested in one with the same id" do
      source = "graph TD\nsubgraph \"a\"\nsubgraph \"a\"\nX\nend\nend\n"

      expect(parses?(source)).to be(false)
    end

    it "still allows two quoted subgraphs with different ids" do
      source = "graph TD\nsubgraph \"a\"\nsubgraph \"b\"\nX\nend\nend\n"

      expect(boxes(source).map(&:id)).to eq(%w[a b])
    end

    # Written the same way, but each gets its own generated id, so
    # neither is the other's parent. mmdc draws both.
    it "allows two free titles written the same way" do
      source = "graph TD\nsubgraph a One\nsubgraph a One\nX\nend\nend\n"

      expect(boxes(source).map(&:id)).to eq(%w[subGraph1 subGraph0])
    end

    # The counter and the containment map used to live on the class, so
    # two threads rendering at once handed out each other's ids.
    #
    # Racing two whole parses does not reach that: a 40-box diagram parses
    # in 23ms, well inside Ruby's 100ms thread quantum, so the two threads
    # run one after the other and agree wherever the state lives. This
    # holds one thread open between its two ids instead, and runs a real
    # parse against it while it waits.
    it "numbers a parse from zero while another thread is mid-parse" do
      transform = Sirena::Parser::Transforms::Flowchart
      opened = Queue.new
      parsed = Queue.new

      other = Thread.new do
        held = transform.state
        ids = [transform.next_generated_id]
        opened.push(:opened)
        parsed.pop
        ids << transform.next_generated_id
        { ids: ids, kept_its_own_state: transform.state.equal?(held) }
      end

      opened.pop
      ours = described_class.new.parse(
        "graph TD\nsubgraph one A\nX\nend\nsubgraph two B\nY\nend\n"
      )
      parsed.push(:parsed)

      expect(ours.subgraphs.map(&:id)).to eq(%w[subGraph0 subGraph1])
      expect(other.value)
        .to eq(ids: %w[subGraph0 subGraph1], kept_its_own_state: true)
    end

    # The memo keeps a reference to every subgraph statement, so holding
    # it after the parse keeps the whole tree alive on a long-lived
    # thread.
    #
    # Both halves, because either alone can be satisfied while the other
    # is false. A second parse numbering from zero is what a caller would
    # see, and it still means something if the state moves off the thread
    # — but it only proves the COUNTER was reset: keep `state[:ids]` and
    # drop the rest and it passes with every statement still referenced.
    # An empty slot is what says the tree was let go.
    it "lets the parse tree go when it is done" do
      parser = described_class.new
      first = parser.parse("graph TD\nsubgraph one A\nX\nend\n")
      second = parser.parse("graph TD\nsubgraph two B\nY\nend\n")

      expect([first, second].map { |d| d.subgraphs.map(&:id) })
        .to eq([%w[subGraph0], %w[subGraph0]])
      expect(Thread.current[:sirena_flowchart_transform]).to be_nil
    end

    it "lets it go even when the parse is refused" do
      parser = described_class.new
      refused = "graph TD\nsubgraph one A\nX\nend\n" \
                "subgraph a\nsubgraph a\nY\nend\nend\n"

      expect { parser.parse(refused) }
        .to raise_error(Sirena::Parser::ParseError)

      expect(parser.parse("graph TD\nsubgraph two B\nZ\nend\n")
                   .subgraphs.map(&:id)).to eq(%w[subGraph0])
      expect(Thread.current[:sirena_flowchart_transform]).to be_nil
    end

    def ids_by_title(source)
      boxes(source).to_h { |box| [box.title, box.id] }
    end

    # A free title makes mermaid generate the id, and it numbers the
    # innermost box first. Ours handed the id out on the way down and
    # asked for it again while checking cycles, so a nested box came out
    # `subGraph2` and the number in between was never used.
    it "numbers a nested generated id from the inside out" do
      source = "graph TD\nsubgraph a One\nsubgraph b Two\nX\nend\nend\n"

      expect(ids_by_title(source))
        .to eq("a One" => "subGraph1", "b Two" => "subGraph0")
    end

    it "numbers three levels from the inside out" do
      source = "graph TD\nsubgraph a One\nsubgraph b Two\nsubgraph c Three\n" \
               "X\nend\nend\nend\n"

      expect(ids_by_title(source)).to eq("a One" => "subGraph2",
                                         "b Two" => "subGraph1",
                                         "c Three" => "subGraph0")
    end

    it "numbers siblings in the order they are written" do
      source = "graph TD\nsubgraph a One\nX\nend\nsubgraph b Two\nY\nend\n"

      expect(ids_by_title(source))
        .to eq("a One" => "subGraph0", "b Two" => "subGraph1")
    end

    # A quoted id carrying whitespace is not an id at all. mermaid
    # generates one and draws the text as the title, trimmed.
    it "generates an id for a quoted id holding a space" do
      expect(ids_by_title("graph TD\nsubgraph \"a b\"\nX\nend\n"))
        .to eq("a b" => "subGraph0")
    end

    it "trims the title it makes from a spaced id" do
      expect(ids_by_title("graph TD\nsubgraph \" ab\"\nX\nend\n"))
        .to eq("ab" => "subGraph0")
    end

    # A bracket title keeps the written id even when it holds a space.
    it "keeps a spaced id that carries a bracket title" do
      expect(ids_by_title("graph TD\nsubgraph \"a b\" [T]\nX\nend\n"))
        .to eq("T" => "a b")
    end

    it "reads a spaced id as part of a free title" do
      expect(ids_by_title("graph TD\nsubgraph \"a b\" T\nX\nend\n"))
        .to eq("a b T" => "subGraph0")
    end

    # The counter lives on the class, so a diagram parsed after another
    # one would carry on from wherever the last diagram stopped.
    it "starts the numbering again for the next diagram" do
      source = "graph TD\nsubgraph a One\nX\nend\n"
      ids_by_title(source)

      expect(ids_by_title(source)).to eq("a One" => "subGraph0")
    end

    # mmdc accepts the source and draws no box for it.
    it "marks a box holding nothing as not worth drawing" do
      expect(only("graph TD\nsubgraph s\nend\nZ\n").drawable?).to be(false)
    end

    it "marks a box holding only another box as worth drawing" do
      found = boxes("graph TD\nsubgraph a\nsubgraph b\nA\nend\nend\n")

      expect(found.map(&:drawable?)).to eq([true, true])
    end
  end

  describe "an empty subgraph" do
    it "parses, though a node-less diagram is refused downstream" do
      # The parser is happy; `Engine#render` rejects a flowchart with no
      # nodes, which it also does for a bare `graph TD` on main. That is a
      # separate gap and not this change's business.
      expect(parses?("graph TD\nsubgraph s\nend\n")).to be(true)
    end

    # The exception to the rule above, and the reason the promotion waits
    # until the whole diagram is read. mmdc 11.12.0 draws no cluster for
    # an empty box and renders `one` and `two` as plain nodes joined by
    # the edge.
    it "stays a node when an edge names it" do
      source = "flowchart TD\nsubgraph one\nend\n" \
               "subgraph two\nend\none --> two\n"

      expect(node_ids(source)).to eq(%w[one two])
    end
  end

  # mmdc 11.12.0 draws no node for a subgraph's id in any of these
  # forms. Each one used to invent a leaf beside the box.
  describe "an id that names a subgraph" do
    it "draws no node when an edge ends on it" do
      source = "flowchart TD\nsubgraph one\nA\nend\n" \
               "subgraph two\nB\nend\none --> two\n"
      diagram = described_class.new.parse(source)

      expect(diagram.nodes.map(&:id)).to eq(%w[A B])
      expect(diagram.edges.map(&:source_id)).to eq(%w[one])
      expect(diagram.edges.map(&:target_id)).to eq(%w[two])
    end

    it "draws no node when the edge came first" do
      source = "flowchart TD\nA --> B\nsubgraph A\nC\nend\n"

      expect(node_ids(source)).to eq(%w[B C])
    end

    it "draws no node when the reference carries a shape" do
      source = "flowchart TD\nsubgraph a\nb[Label]\nend\n" \
               "subgraph b\nX\nend\n"
      diagram = described_class.new.parse(source)

      expect(diagram.nodes.map(&:id)).to eq(%w[X])
      expect(diagram.subgraphs.map(&:parent_id)).to eq([nil, "a"])
    end

    it "leaves a box written inside another where it was written" do
      source = "flowchart TD\nsubgraph a\nsubgraph b\nX\nend\nend\n" \
               "subgraph c\nb\nend\n"
      boxes = described_class.new.parse(source).subgraphs
      held = boxes.to_h { |box| [box.id, box] }

      expect(held["b"].parent_id).to eq("a")
      expect(held["c"].node_ids).to be_empty
    end
  end

  # mmdc 11.12.0 lays `subgraph s` / `direction LR` / `A --> B` / `end`
  # out horizontally. This used to throw the whole diagram away at `LR`.
  describe "a direction inside a subgraph" do
    it "is accepted" do
      source = "flowchart TD\nsubgraph s\ndirection LR\nA --> B\nend\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "is kept on the box" do
      source = "flowchart TD\nsubgraph s\ndirection LR\nA --> B\nend\n"

      expect(described_class.new.parse(source).subgraphs.first.direction)
        .to eq("LR")
    end

    # A semicolon separates this statement from the next, the way it
    # separates every other one. mmdc 11.12.0 renders `direction LR;A`,
    # and ending on `line_end` refused it.
    it "lets a semicolon follow it" do
      source = "graph TD\nsubgraph s\ndirection LR;A\nB --> A\nend\n"
      diagram = described_class.new.parse(source)

      expect(diagram.subgraphs.first.direction).to eq("LR")
      expect(diagram.nodes.map(&:id)).to contain_exactly("A", "B")
    end

    # The header's aliases are header-only. mmdc 11.12.0 draws `graph <`,
    # `graph v` and `graph BR`, and refuses all three after `direction`.
    ["<", ">", "^", "v", "BR"].each do |alias_form|
      it "refuses the header alias #{alias_form}" do
        source = "flowchart TD\nsubgraph s\ndirection #{alias_form}\n" \
                 "A --> B\nend\n"

        expect(parses?(source)).to be(false)
      end
    end

    # mmdc accepts a top-level one and ignores it: `flowchart TD` then
    # `direction LR` still stacks its nodes vertically.
    it "is accepted and ignored at the top level" do
      source = "flowchart TD\ndirection LR\nA --> B\n"
      diagram = described_class.new.parse(source)

      expect(diagram.nodes.map(&:id)).to eq(%w[A B])
      expect(diagram.direction).to eq("TD")
    end
  end

  # A flat chain nests nothing, so the grammar's own depth guard never
  # fires. The cycle walk recursed anyway and raised a bare
  # SystemStackError straight out of the parse.
  describe "a long chain of boxes" do
    it "is checked for cycles without recursing" do
      chain = (0...4_000).map { |i| "subgraph s#{i}\ns#{i + 1}\nend\n" }.join

      expect { described_class.new.parse("graph TD\n#{chain}s4000\n") }
        .not_to raise_error
    end
  end
end
