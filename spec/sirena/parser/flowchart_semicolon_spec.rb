# frozen_string_literal: true

require "spec_helper"
require "timeout"

RSpec.describe Sirena::Parser::FlowchartParser do
  # The corpus cannot verify most of this. A naive version of this change —
  # widening `line_end` itself — passes the whole sweep and the whole suite
  # while breaking `style`, `classDef` and `click`, because no corpus case
  # puts a `;` inside a style property list. Every guard below is written by
  # hand against mmdc 11.12.0 for that reason.
  let(:engine) { Sirena::Engine.new }

  def node_ids(source)
    described_class.new.parse(source).nodes.map(&:id).sort
  end

  def renders?(source)
    engine.render(source)
    true
  rescue Sirena::Engine::PipelineError, Sirena::Engine::DiagramTypeError
    false
  end

  describe "accepting `;` as a separator" do
    {
      "after the header" => "graph TD;\nA-->B\n",
      "between statements on one line" => "graph TD\nA-->B;C-->D\n",
      "with leading whitespace" => "graph TD\nA-->B ;C\n",
      "repeated" => "graph TD\nA-->B;;;C\n",
      "on the header and repeated" => "graph TD;;A-->B;;;C-->D;;\n",
      "trailing before EOF" => "graph TD\nA-->B;\n"
    }.each do |label, source|
      it "accepts a separator #{label}" do
        expect(renders?(source)).to be(true)
      end
    end
  end

  describe "rules that scan to the physical end of a line" do
    # These four render on main and in mmdc. They are the regressions the
    # rejected design would have caused: both rules are written as
    # `line_end.absent?`, so widening `line_end` truncates them at the `;`.
    {
      "style with two properties" =>
        "graph TD\nA-->B\nstyle A fill:#f9f;stroke:#333\n",
      "classDef with two properties" =>
        "graph TD\nA-->B\nclassDef foo fill:#f9f;stroke:#333\n",
      "click with a semicolon in the URL" =>
        %(graph TD\nA\nclick A "https://example.com/a;b"\n),
      "click mixing bare tokens and quoted strings" =>
        %(graph TD\nA\nclick A href "https://example.com/a;b" "tip;here" _blank\n)
    }.each do |label, source|
      it "still renders #{label}" do
        expect(renders?(source)).to be(true)
      end
    end
  end

  describe "statements after a separator survive" do
    # Scanning a value to the end of the line swallowed whatever followed a
    # `;`, so these parsed and then silently rendered one node short. mmdc
    # renders B in every case. Asserted on the model, because the render
    # succeeds either way and the corpus scores it a pass.
    {
      "style" => "graph TD\nA\nstyle A fill:red;B\n",
      "classDef" => "graph TD\nA\nclassDef x fill:red;B\n",
      "click" => %(graph TD\nA\nclick A "http://x";B\n)
    }.each do |label, source|
      it "keeps a node after a #{label} statement" do
        expect(node_ids(source)).to eq(%w[A B])
      end
    end

    it "still reads two declarations as one list" do
      # Node ids alone cannot see this: they are the same whether the
      # second declaration joined the list or was dropped. The captured
      # properties are the tell — deleting the capture left this green.
      source = "graph TD\nA-->B\nstyle A fill:#f9f;stroke:#333\n"
      tree = Sirena::Parser::Grammars::Flowchart.new.parse(source)
      props = Array(tree).find { |n| n.is_a?(Hash) && n.key?(:style_props) }

      expect(node_ids(source)).to eq(%w[A B])
      expect(props[:style_props].to_s.strip).to eq("fill:#f9f;stroke:#333")
    end
  end

  # A `#` in the value changes what the `;` means, and that is the whole
  # rule. mermaid's lexer reads the `#` as a token that eats the `;` and
  # carries on to the end of the line, so `style A fill:#f9f;B` draws A
  # alone while `style A fill:red;B` draws A and B. Deciding on the text
  # after the `;` invented a node B here that main never drew.
  describe "a hash in a declaration value" do
    {
      "style" => "graph TD\nA\nstyle A fill:#f9f;B\n",
      "classDef" => "graph TD\nA\nclassDef x fill:#f9f;B\n"
    }.each do |label, source|
      it "swallows what follows the separator on a #{label}" do
        expect(node_ids(source)).to eq(%w[A])
      end
    end

    it "leaves the separator alone when the value has no hash" do
      expect(node_ids("graph TD\nA\nstyle A fill:red;B\n")).to eq(%w[A B])
    end

    # A `#` later on the line arrives too late — the `;` already ended the
    # statement. mmdc draws both nodes in each of these.
    {
      "in a node label" => ["graph TD\nA\nstyle A fill:red;B[#x]\n", %w[A B]],
      "in an edge label" =>
        ["graph TD\nA\nstyle A fill:red;B-->|#x|C\n", %w[A B C]]
    }.each do |label, (source, ids)|
      it "does not reach back for a hash #{label}" do
        expect(node_ids(source)).to eq(ids)
      end
    end

    it "does not reach back for a hash after the separator" do
      # The `;` comes first, so it ends the statement and the hash never
      # gets to swallow anything. mmdc draws A and a node `stroke:#333`;
      # a node id here takes no colon, so we refuse instead of drawing a
      # diagram one node short.
      expect { described_class.new.parse("graph TD\nA\nstyle A fill:red;stroke:#333\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "still ends at the newline" do
      expect(node_ids("graph TD\nA\nstyle A fill:#f9f\nB\n")).to eq(%w[A B])
    end

    it "does not reach forward to a hash on the next line" do
      expect(node_ids("graph TD\nA\nstyle A fill:red\nB[#x]\n")).to eq(%w[A B])
    end

    # A comma splits mermaid's declaration list and we model none of that,
    # with or without a hash. mmdc draws node A for both of these; we refuse
    # the line, exactly as main does. Pinned so the two paths cannot drift.
    [
      "style A fill:red,stroke:blue",
      "style A fill:#f9f,stroke:blue"
    ].each do |declaration|
      it "refuses #{declaration.inspect}" do
        expect(renders?("graph TD\nA\n#{declaration}\n")).to be(false)
      end
    end
  end

  describe "click requires an action" do
    # mmdc rejects a bare `click A`, so an optional action let a separator
    # turn `click A;B` into an actionless click plus a node.
    it "rejects a bare click" do
      expect(renders?("graph TD\nA\nclick A\n")).to be(false)
    end

    it "rejects an actionless click followed by a separator" do
      expect(renders?("graph TD\nA\nB\nclick A;B\n")).to be(false)
    end
  end

  describe "declarations mermaid accepts loosely" do
    # Requiring `name:value` here rejected five forms main accepted and mmdc
    # renders. Only the decision after a `;` is strict now.
    [
      "style A  fill:red",
      "style A fill :red",
      "style A fill:",
      "style A red",
      "classDef x red"
    ].each do |declaration|
      it "still accepts #{declaration.inspect}" do
        expect(renders?("graph TD\nA\n#{declaration}\n")).to be(true)
      end
    end

    # Loose is not empty. mmdc refuses a declaration carrying no
    # properties at all, trailing space and all.
    ["style A ", "classDef x "].each do |declaration|
      it "refuses #{declaration.inspect}" do
        expect(renders?("graph TD\nA\n#{declaration}\n")).to be(false)
      end
    end
  end

  # The guard belongs on every target that takes a node id, not just the
  # ones a statement can start with. mmdc refuses `style end fill:red` and
  # `class end foo`, and takes `click end "u"` — a click target is a real
  # node id there, so that one stays ungated.
  describe "a statement keyword is not a declaration target" do
    ["style end fill:red", "class end foo", "style graph fill:red",
     "class subgraph foo"].each do |declaration|
      it "refuses #{declaration.inspect}" do
        expect { described_class.new.parse("graph TD\nA\n#{declaration}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "still takes a click target that reads like one" do
      expect(node_ids(%(graph TD\nA\nclick end "u"\n))).to eq(%w[A])
    end

    it "still takes a target that merely starts with a keyword" do
      expect(node_ids("graph TD\nendpoint\nstyle endpoint fill:red\n"))
        .to eq(%w[endpoint])
    end
  end

  describe "a statement keyword is not a node" do
    # A malformed directive used to fall through to the node rules, so
    # `click ;B` produced nodes `click` and `B`. mmdc rejects all of these.
    ["click ;B", "style ;B", "class ;B"].each do |source|
      it "rejects #{source.inspect}" do
        expect(renders?("graph TD\nA\nB\n#{source}\n")).to be(false)
      end
    end

    it "leaves a node whose name merely starts with a keyword alone" do
      expect(renders?("graph TD\nendpoint-->classy\n")).to be(true)
    end
  end

  describe "a space before the separator" do
    # mmdc takes it on a node statement and refuses it on the header or a
    # class assignment, so one shared separator over-accepted two forms.
    it "is allowed on a node statement" do
      expect(renders?("graph TD\nA-->B ;C\n")).to be(true)
    end

    it "is refused on the header" do
      expect(renders?("graph TD ;A\n")).to be(false)
    end

    it "is refused on a class assignment" do
      expect(renders?("graph TD\nA\nB\nclass A foo ;B\n")).to be(false)
    end

    it "is refused between a click action and the separator" do
      # The action ran up to the space and left ` ;B` for the terminator,
      # which produced a node B. mmdc rejects the source outright.
      expect(renders?(%(graph TD\nA\nclick A "u" ;B\n))).to be(false)
    end
  end

  describe "a separator standing on its own" do
    # mermaid takes a separator where a statement would go. Requiring a
    # statement before every separator rejected all three.
    {
      "opening a line after the header" => "graph TD;\n;A-->B\n",
      "alone on a line" => "graph TD\nA\n;\nB\n",
      "trailing after a statement" => "graph TD\nA\n;\n"
    }.each do |label, source|
      it "accepts one #{label}" do
        expect(renders?(source)).to be(true)
      end
    end

    it "is still refused on the header line" do
      # `graph TD ;A` is rejected by mmdc, and allowing a bare separator as
      # a statement let it back in.
      expect(renders?("graph TD ;A\n")).to be(false)
    end
  end

  describe "an inline class after a separator" do
    it "keeps the node rather than reading it as a declaration" do
      # `:::` is an inline class, never a declaration colon. The lookahead
      # saw `B` then a colon and swallowed the node silently.
      expect(node_ids("graph TD\nA\nstyle A fill:red;B:::foo\n"))
        .to eq(%w[A B])
    end

    it "refuses a second declaration it cannot spell as a node" do
      # Without a hash the `;` always ends the statement, so `stroke:blue`
      # has to stand as a node. mmdc draws exactly that. A node id here
      # takes no colon, so we refuse the line — swallowing it drew A and B
      # and silently lost the third node.
      expect { described_class.new.parse("graph TD\nA-->B\nstyle A fill:red;stroke:blue\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  # A keyword is not a node wherever a node is built, and an edge target
  # is one of those places. The statement-leading guards missed it, so
  # `A-->end` made a node mmdc refuses.
  describe "a keyword as an edge target" do
    it "is refused" do
      expect { described_class.new.parse("graph TD;A-->end;B\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "still takes an ordinary target" do
      expect(node_ids("graph TD;A-->B;C\n")).to eq(%w[A B C])
    end
  end

  # A word direction needs a gap after the keyword; a glyph one does not.
  describe "a glyph direction" do
    %w[< > ^].each do |glyph|
      it "needs no space before #{glyph}" do
        expect(node_ids("graph#{glyph}\nA-->B\n")).to eq(%w[A B])
      end

      it "still takes a space before #{glyph}" do
        expect(node_ids("graph #{glyph}\nA-->B\n")).to eq(%w[A B])
      end
    end

    it "does not let a word direction lose its gap" do
      expect { described_class.new.parse("graphTD\nA-->B\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  # A separator closes the header only when a direction came first.
  describe "a separator straight after the keyword" do
    it "is refused without a direction" do
      expect { described_class.new.parse("graph;A\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "is taken after one" do
      expect(node_ids("graph TD;A\n")).to eq(%w[A])
    end
  end

  # `click` opens a directive when a space, a newline or nothing follows.
  # A semicolon does none of those, and testing it with `line_end` — which
  # swallows one — refused three diagrams mmdc draws.
  describe "click against a separator" do
    {
      "before a newline" => ["graph TD;click;\nB\n", %w[B click]],
      "at end of input" => ["graph TD;click;\n", %w[click]],
      "before another node" => ["graph TD;click;B\n", %w[B click]]
    }.each do |label, (source, ids)|
      it "is an ordinary node #{label}" do
        expect(node_ids(source)).to eq(ids)
      end
    end

    it "still opens a directive when a space follows" do
      source = "graph TD\nA\nclick A \"https://example.com\"\n"

      expect(node_ids(source)).to eq(%w[A])
    end
  end

  # `classDef` has to be tried before `class`, because Parslet does not
  # backtrack into an alternative that already matched. Swapping them made
  # `classDef[x]` a node and left every example green.
  describe "the keyword alternation order" do
    { "classDef" => "graph TD\nclassDef[x]\n",
      "class" => "graph TD\nclass[x]\n" }.each do |word, source|
      it "refuses #{word} carrying a shape" do
        expect { described_class.new.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "still takes a classDef statement" do
      source = "graph TD\nA-->B\nclassDef foo fill:#f9f\n"

      expect { described_class.new.parse(source) }.not_to raise_error
    end
  end

  describe "a declaration key outside ASCII" do
    it "is not a declaration, and mermaid refuses the line" do
      # This example asserted the opposite and was wrong. mmdc 11.12.0
      # rejects `é: value`, so treating it as a continuation accepted a
      # source the oracle refuses.
      expect { described_class.new.parse("graph TD\nA\nstyle A fill:red;é: value\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  # Reading the key as "anything up to a colon" made `|x:y|` look like a
  # declaration, so the edge and both its nodes vanished.
  describe "an edge label after a declaration" do
    it "keeps the edge and both its nodes" do
      source = "graph TD;A;style A fill:red;B-->|x:y|C\n"

      expect(node_ids(source)).to eq(%w[A B C])
    end

    it "keeps the label itself" do
      # The pipes are still in the label, here and on main. mmdc's label is
      # `x:y`; stripping them is an edge-label fix, not a separator one, so
      # this asserts what we do rather than pretending it is right.
      source = "graph TD;A;style A fill:red;B-->|x:y|C\n"
      diagram = described_class.new.parse(source)

      expect(diagram.edges.map(&:label)).to eq(["|x:y|"])
    end
  end

  # The direction shares the keyword's line and owns the rest of it.
  describe "the header line" do
    {
      "a separator touching the direction" => "graph TD;A\n",
      "a newline after the direction" => "graph TD\nA\n",
      "the keyword alone" => "graph\nA\n"
    }.each do |label, source|
      it "takes #{label}" do
        expect { described_class.new.parse(source) }.not_to raise_error
      end
    end

    {
      "a separator standing off the direction" => "graph TD ;A\n",
      "a separator with no direction" => "graph ;A\n",
      "a word that is not a direction" => "graph X;A\n",
      "a direction with a letter stuck to it" => "graph TDx\nA-->B\n",
      "a direction with a digit stuck to it" => "graph TD2\nA-->B\n"
    }.each do |label, source|
      it "refuses #{label}" do
        expect { described_class.new.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "leaves a direction on the next line as a node" do
      # mmdc reads this as a diagram with nodes TD and A.
      expect(node_ids("graph\nTD;A\n")).to eq(%w[A TD])
    end
  end

  # mermaid's full direction set. Reading an alias as a node left a stray
  # `BR` or `v` in the diagram.
  #
  # The aliases also have to reach the model as a direction word. mmdc lays
  # `graph <` out exactly like `graph RL`, `>` like `LR` and `^` like `BT` —
  # measured from where the two nodes of `A --- B` land. The graph transform
  # only knows the words, so a surviving glyph fell to its default and drew
  # all three top-to-bottom.
  describe "direction aliases" do
    {
      "TD" => "TD",
      "TB" => "TB",
      "BT" => "BT",
      "LR" => "LR",
      "RL" => "RL",
      "BR" => "TB",
      "v" => "TB",
      "<" => "RL",
      ">" => "LR",
      "^" => "BT"
    }.each do |token, direction|
      it "takes #{token} without making it a node" do
        expect(node_ids("graph #{token}\nA-->B\n")).to eq(%w[A B])
      end

      it "reads #{token} as #{direction}" do
        diagram = described_class.new.parse("graph #{token}\nA-->B\n")

        expect(diagram.direction).to eq(direction)
      end
    end

    # The point of the words: this is the mapping the finding was about.
    it "carries a glyph through to the layout direction" do
      layouts = %w[< > ^].to_h do |glyph|
        diagram = described_class.new.parse("graph #{glyph}\nA-->B\n")
        graph = Sirena::Transform::FlowchartTransform.new.to_graph(diagram)

        [glyph, graph[:layoutOptions]["elk.direction"]]
      end

      expect(layouts).to eq("<" => "LEFT", ">" => "RIGHT", "^" => "UP")
    end
  end

  # These are keywords wherever they appear, and the boundary is a word
  # boundary: `style[x]` and `_blank-->Z` slipped through a space-only test.
  describe "words that are never node ids" do
    %w[_blank _self _parent _top].each do |word|
      it "refuses #{word} as a node" do
        expect { described_class.new.parse("graph TD\n#{word}-->Z\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "refuses a keyword carrying a shape" do
      expect { described_class.new.parse("graph TD\nstyle[x]\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "still takes a word that merely starts with one" do
      expect(node_ids("graph TD\n_blanket-->Z\n")).to eq(%w[Z _blanket])
    end
  end

  # The callback name runs to its opening paren, so a semicolon inside it
  # is name text rather than a separator.
  describe "a call action" do
    {
      "two spaces after call" => "graph TD\nA\nclick A call  cb()\n",
      "a namespaced name" => "graph TD\nA\nclick A call ns.cb()\n",
      "a semicolon in the name" => "graph TD\nA\nclick A call cb;B()\n"
    }.each do |label, source|
      it "takes #{label}" do
        expect { described_class.new.parse(source) }.not_to raise_error
      end
    end

    it "does not leave a node behind a semicolon in the name" do
      # Splitting on the `;` invented a node called B.
      expect(node_ids("graph TD\nA\nclick A call cb;B()\n")).to eq(%w[A])
    end

    # mermaid stops caring about line structure inside a callback, so
    # whitespace and comments are ignorable after `call` and again before
    # the `(`. mmdc draws node A alone for every one of these; spaces alone
    # left a stray `cb` node on the following line.
    {
      "a newline" => "graph TD\nA\nclick A call\ncb()\n",
      "a newline and a space" => "graph TD\nA\nclick A call\n cb()\n",
      "a blank line" => "graph TD\nA\nclick A call\n\ncb()\n",
      "a comment line" => "graph TD\nA\nclick A call\n%% c\ncb()\n",
      "a trailing comment" => "graph TD\nA\nclick A call %% c\ncb()\n",
      "a newline before the parens" => "graph TD\nA\nclick A call cb\n()\n",
      "a blank line before the parens" =>
        "graph TD\nA\nclick A call cb\n\n()\n",
      "a comment before the parens" =>
        "graph TD\nA\nclick A call cb\n%% c\n()\n",
      "a trailing comment before the parens" =>
        "graph TD\nA\nclick A call cb %% c\n()\n"
    }.each do |label, source|
      it "reaches across #{label}" do
        expect(node_ids(source)).to eq(%w[A])
      end
    end

    it "still stops the name at the end of its line" do
      # mermaid keeps reading: mmdc draws A alone here, having swallowed
      # the whole `B --> C` edge into the callback name. Following it there
      # would let a callback eat statements we can still draw, so we refuse
      # instead. This asserts what we do, not what mermaid does.
      expect(renders?("graph TD\nA\nclick A call cb\nB --> C\nD()\n"))
        .to be(false)
    end

    # Once `call` opens a callback the parens are compulsory. Falling back
    # to a plain action accepted every one of these; mmdc exits 1 on all
    # four.
    [
      "click A call cb",
      "click A call cb(",
      "click A call",
      "click A call cb() _blank"
    ].each do |statement|
      it "refuses #{statement.inspect}" do
        expect(renders?("graph TD\nA\n#{statement}\n")).to be(false)
      end
    end

    it "refuses a callback that runs into the next line" do
      expect(renders?("graph TD\nA\nclick A call\nB\n")).to be(false)
    end

    it "still takes a quoted tooltip after the parens" do
      expect(renders?(%(graph TD\nA\nclick A call cb() "tip"\n))).to be(true)
    end

    it "leaves a word that merely starts with call alone" do
      # `calling()` is not a callback, and mmdc refuses it for the parens.
      expect(renders?("graph TD\nA\nclick A calling()\n")).to be(false)
    end
  end

  # A bare paren is not click-action text. mmdc refuses `click A cb()` and
  # `click A "u" (1)`, and the old rule only caught the forms that also
  # carried a `;`.
  describe "a paren outside a callback" do
    ["click A cb()", "click A cb(1)", %(click A "http://x" (1))]
      .each do |statement|
      it "refuses #{statement.inspect}" do
        expect(renders?("graph TD\nA\n#{statement}\n")).to be(false)
      end
    end

    it "is ordinary inside quotes" do
      expect(renders?(%(graph TD\nA\nclick A "http://x(y)"\n))).to be(true)
    end
  end

  # `href` and `call` are directive words exactly where `click` is: mmdc
  # refuses them as node ids before a space, a newline or the end of input,
  # and draws them as nodes before a `;` or a shape. Reserving only `click`
  # let `href --- B` and `call --- B` through.
  describe "href and call as node ids" do
    %w[href call].each do |word|
      it "refuses #{word} before a space" do
        expect(renders?("graph TD\n#{word} --- B\n")).to be(false)
      end

      it "refuses #{word} before a newline" do
        expect(renders?("graph TD\n#{word}\nB\n")).to be(false)
      end

      it "refuses #{word} at end of input" do
        expect(renders?("graph TD\n#{word}")).to be(false)
      end

      it "refuses #{word} as an edge target" do
        expect(renders?("graph TD\nA --- #{word}\n")).to be(false)
      end

      it "takes #{word} before a separator" do
        expect(node_ids("graph TD;#{word};B\n")).to eq(["B", word])
      end

      it "takes #{word} carrying a shape" do
        expect(node_ids("graph TD\n#{word}[x]\n")).to eq([word])
      end
    end

    it "leaves a word that merely starts with one alone" do
      expect(node_ids("graph TD\ncaller --- hrefs\n")).to eq(%w[caller hrefs])
    end
  end

  describe "a semicolon after a subgraph's end" do
    it "may stand off it, as far as the grammar is concerned" do
      # mmdc renders `end ;B` and the grammar used to refuse it. Asserted
      # on the grammar because the transform now refuses every subgraph:
      # the model has no container to put one in, and drawing loose nodes
      # where mermaid draws a cluster would be a wrong picture.
      source = "graph TD\nsubgraph s\nA\nend ;B\n"

      expect { Sirena::Parser::Grammars::Flowchart.new.parse(source) }
        .not_to raise_error
    end

    it "is still refused past the grammar, with a reason" do
      expect { described_class.new.parse("graph TD\nsubgraph s\nA\nend ;B\n") }
        .to raise_error(Sirena::Parser::ParseError, /subgraphs are not supported/)
    end
  end

  # The guard is on the parsed marker, not the source text.
  describe "the subgraph refusal" do
    it "does not catch the word in a label" do
      expect(node_ids("graph TD\nA[subgraph here] --- B\n")).to eq(%w[A B])
    end

    it "does not catch an id that starts with it" do
      expect(node_ids("graph TD\nsubgraphs --- B\n")).to eq(%w[B subgraphs])
    end
  end

  describe "parentheses in a click action" do
    it "belong to a callback" do
      expect(renders?("graph TD\nA\nclick A call cb(foo;bar)\n")).to be(true)
    end

    it "are not special anywhere else" do
      # mmdc rejects this; treating every action's parens as a group let it
      # through.
      expect(renders?("graph TD\nA\nclick A nope(foo;bar)\n")).to be(false)
    end
  end

  describe "keywords that are not node ids" do
    { "end" => "graph TD;end;B\n",
      "graph" => "graph TD;graph;B\n",
      "flowchart" => "graph TD;flowchart;B\n" }.each do |name, source|
      it "refuses a bare #{name}" do
        expect(renders?(source)).to be(false)
      end
    end

    it "refuses a bare click" do
      expect(renders?("graph TD\nA\nclick\n")).to be(false)
    end

    it "still treats click before an unspaced separator as a node" do
      expect(node_ids("graph TD;click;B\n")).to eq(%w[B click])
    end
  end

  describe "a colon that is not a declaration" do
    # The continuation lookahead took any text before a colon, so a node
    # label containing one looked like another property and got swallowed.
    {
      "style" => "graph TD\nA\nstyle A fill:red;B(foo:bar)\n",
      "classDef" => "graph TD\nA\nclassDef x f:r;B(foo:bar)\n"
    }.each do |label, source|
      it "keeps a node with a colon in its label after #{label}" do
        expect(node_ids(source)).to eq(%w[A B])
      end
    end
  end

  describe "a semicolon inside a callback argument" do
    it "belongs to the callback, not the statement" do
      expect(renders?("graph TD\nA\nclick A call cb(foo;bar)\n")).to be(true)
    end

    it "still separates after the closing paren" do
      source = "graph TD\nA\nclick A call cb(foo;bar);B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end
  end

  describe "a comment on the same line as a separator" do
    # mmdc rejects the same-line form and takes the newline form. `space?`
    # never crosses a newline, so one guard separates them.
    [
      "graph TD;%% c;D",
      "graph TD\nA;;%% c;D",
      "graph TD\nA ;%% c;D",
      "graph TD\nA;%% c;D"
    ].each do |source|
      it "rejects #{source.lines.last.chomp.inspect}" do
        expect(renders?("#{source}\n")).to be(false)
      end
    end

    it "still takes a comment on the next line" do
      expect(renders?("graph TD\nA-->B;\n%% comment\n")).to be(true)
    end
  end

  # Mermaid strips comments with `/^\s*%%(?!{)[^\n]+\n?/gm`, read from
  # mermaid 11.12.0's own `cleanupComments`. The `^` is anchored to a line
  # start, so a `%%` with a statement in front of it is never stripped and
  # never a comment — it is content, and mmdc reads `A%%c` as one node
  # called `A%%c`.
  #
  # `line_end` used to end a statement at such a `%%`. That was wrong for
  # every input it took, in one of two ways, and both are pinned below.
  # Three scanners are defined as running "up to `line_end`", so ending a
  # statement at a `%%` quietly shortened all three. They now run past it,
  # which is what mermaid does — it strips a comment only at a line start,
  # so a mid-line `%%` is ordinary text.
  #
  # Nothing downstream reads either value today, so the change is invisible
  # in the SVG. Pinned here because "invisible" is exactly how it would rot.
  describe "a %% inside a declaration the scanners read" do
    def capture(source, key)
      tree = Sirena::Parser::Grammars::Flowchart.new.parse(source)
      found = nil
      walk = lambda do |node|
        case node
        when Array then node.each { |child| walk.call(child) }
        when Hash
          found ||= node[key].to_s if node.key?(key)
          node.each_value { |child| walk.call(child) }
        end
      end
      walk.call(tree)
      found
    end

    it "keeps a spaced %% in a style property list" do
      source = "graph TD\nA-->B\nstyle A fill:red %% c\n"

      expect(capture(source, :style_props)).to eq(" fill:red %% c")
    end

    it "keeps an abutting %% in a click callback name" do
      source = "graph TD\nA-->B\nclick A cb%%c\n"

      expect(capture(source, :click_action)).to eq("cb%%c")
    end

    # Neither value reaches the renderer, so the widened text cannot change
    # a diagram. If that stops being true, this is the example that says so.
    {
      "a style property list" => ["style A fill:red %% c", "style A fill:red"],
      "a click callback" => ["click A cb%%c", "click A cb"]
    }.each do |label, (with_comment, without)|
      it "draws #{label} the same either way" do
        widened = engine.render("graph TD\nA-->B\n#{with_comment}\n").to_s
        plain = engine.render("graph TD\nA-->B\n#{without}\n").to_s

        expect(widened).to eq(plain)
      end
    end

    # The class name is the one of the three that does NOT run past it: a
    # `%` cannot be in a class name here. mmdc draws this with the name
    # `foo%%c`, so it is an under-acceptance, and closing it is the same
    # `%`-in-a-name widening this PR declines to make for node ids.
    it "refuses an abutting %% in a class name, which mmdc draws" do
      expect(renders?("graph TD\nA-->B\nclass A foo%%c\n")).to be(false)
    end
  end

  describe "a comment at the end of a statement line" do
    # With a gap in front of it mmdc refuses the whole diagram, and this
    # used to draw the statement. Widening node ids is what brought the
    # numeric and non-ASCII rows into the same arm.
    [
      "graph TD\nA %% c",
      "graph TD\n1 %% c",
      "graph TD\né %% c",
      "graph TD\nA-->B %% c",
      "graph TD\n1-->2 %% c",
      "graph TD\nA[T] %% c",
      "graph TD\nA-->B\nclass A foo %% c",
      "graph TD\nA-->B\nclick A \"u\" %% c"
    ].each do |source|
      it "refuses #{source.lines.last.chomp.inspect}, as mmdc does" do
        expect(renders?("#{source}\n")).to be(false)
      end
    end

    # Tight against the statement mmdc draws it, as part of the node's own
    # name. This refuses it rather than drawing `A` and dropping the rest,
    # and closing the gap means letting `%` into a node id — a widening
    # this PR does not make.
    it "refuses A%%c, which mmdc reads as one node called A%%c" do
      expect(renders?("graph TD\nA%%c\n")).to be(false)
    end

    # A comment on its OWN line is untouched by all of this: it is the one
    # shape mermaid's regex actually strips, leading whitespace and all.
    {
      "on the line after a statement" => "graph TD\nA\n%% c\n",
      "indented on its own line" => "graph TD\nA\n  %% c\n",
      "after a statement and a separator" => "graph TD\nA;\n%% c\n",
      "before every statement" => "graph TD\n%% c\nA\n"
    }.each do |label, source|
      it "still takes a comment #{label}" do
        expect(renders?(source)).to be(true)
      end
    end
  end

  describe "the separator rule itself" do
    # `statement_end` must never be repeated directly: its `line_end` arm
    # succeeds zero-width at EOF, so repeating it would spin forever. Getting
    # that wrong makes these two spin, not fail, so each one carries its own
    # timeout — a hung suite is worse than a red one. They are asserted at
    # the parser rather than through the engine because a node-less flowchart
    # is rejected downstream on main too, for unrelated reasons.
    it "terminates on a header followed only by separators" do
      expect { Timeout.timeout(5) { described_class.new.parse("graph TD;;;\n") } }
        .not_to raise_error
    end

    it "terminates on separators at end of input" do
      expect { Timeout.timeout(5) { described_class.new.parse("graph TD\nA-->B;;;") } }
        .not_to raise_error
    end
  end

  # A hash lets the declaration carry one `;`, and only one. mmdc refuses a
  # second, and refuses a shape or an edge behind the first. Swallowing the
  # whole line accepted every source in the first list.
  describe "the tail after a hashed declaration" do
    [
      "style A fill:#f9f;B;C",
      # A trailing `;` is a second separator too. `line_end` swallows one,
      # so a lookahead through it let these past the one-`;` rule.
      "style A fill:#f9f;B;",
      "style A fill:#f9f;B ;",
      "classDef x fill:#f9f;B;",
      "style A fill:#f9f;;B",
      "style A fill:#f9f;B ;C",
      "style A fill:#f9f;stroke:#333;color:#fff",
      "style A fill:#f9f;B[x]",
      "style A fill:#f9f;B]",
      "style A fill:#f9f;B(x)",
      "style A fill:#f9f;B)",
      "style A fill:#f9f;B{x}",
      "style A fill:#f9f;B}",
      "style A fill:#f9f;B<C",
      "style A fill:#f9f;B|C",
      "style A fill:#f9f;B~C",
      "style A fill:#f9f;B@C",
      "style A fill:#f9f;B=C",
      "style A fill:#f9f;B^C",
      "style A fill:#f9f;B-->C",
      "classDef x fill:#f9f;B;C"
    ].each do |declaration|
      it "refuses #{declaration.inspect}" do
        expect(renders?("graph TD\nA\n#{declaration}\n")).to be(false)
      end
    end

    [
      "style A fill:#f9f;B",
      "style A fill:#f9f; B",
      "style A fill:#f9f;",
      "style A fill:#f9f;a b",
      "style A fill:#f9f;B-C",
      "style A fill:#f9f;B/C",
      "style A fill:#f9f;B\tC",
      %(style A fill:#f9f;B"C),
      "style A fill:#f9f;stroke-width:2px",
      "style A fill:#f9f;stroke:#333",
      "classDef x fill:#f9f;stroke:#333"
    ].each do |declaration|
      it "takes #{declaration.inspect}" do
        expect(node_ids("graph TD\nA\n#{declaration}\n")).to eq(%w[A])
      end
    end
  end

  # A hashed tail and a bare callback name both stop where mermaid keeps
  # the text for itself, and some of what it keeps is longer than one
  # character. Every character in `--`, `-.` and `:::` is ordinary alone,
  # so checking one at a time waves all three through in both places.
  describe "structural tokens longer than one character" do
    [
      "style A fill:#f9f;B---C",
      "style A fill:#f9f;B--C",
      "style A fill:#f9f;B-.-C",
      "style A fill:#f9f;B-.C",
      "style A fill:#f9f;B:::foo",
      "style A fill:#f9f;B--",
      "style A fill:#f9f;B-.",
      "style A fill:#f9f;B:::",
      "click A cb--x",
      "click A cb-.x",
      "click A cb:::x",
      "click A cb--",
      "click A cb-.",
      "click A cb:::"
    ].each do |statement|
      it "refuses #{statement.inspect}" do
        expect(renders?("graph TD\nA\n#{statement}\n")).to be(false)
      end
    end

    # The same characters standing alone stay ordinary text. Without these
    # the guard could widen to every `-`, `.` and `:` unnoticed.
    [
      "style A fill:#f9f;B.C",
      "style A fill:#f9f;B:C",
      "style A fill:#f9f;B::C",
      "style A fill:#f9f;B-",
      "click A cb-x",
      "click A cb.x",
      "click A cb:x",
      "click A cb::x"
    ].each do |statement|
      it "takes #{statement.inspect}" do
        expect(node_ids("graph TD\nA\n#{statement}\n")).to eq(%w[A])
      end
    end
  end

  # mermaid takes four click actions and nothing else. Scanning to the end
  # of the line accepted the junk after a good one and, once `;` became a
  # separator, drew a node out of it.
  describe "the shape of a click action" do
    [
      %(click A "u" nope),
      %(click A "u"\)),
      %(click A "u" _blank "tip"),
      %(click A "u" "t" "x"),
      "click A cb _blank",
      "click A cb nope",
      %(click A cb "tip" _blank),
      "click A my callback",
      "click A href",
      "click A href ",
      "click A click",
      "click A style",
      "click A end",
      "click A graph",
      "click A subgraph",
      "click A _blank",
      "click A href _self",
      "click A href cb",
      %(click A href "u" nope),
      %(click A href "u" "t" "x"),
      # mermaid counts the whitespace between these tokens: exactly one
      # space or one tab. Two of either is an error, and `repeat(1)` let
      # every one of these through — and once `;` became a separator they
      # drew a node B out of a line mmdc refuses.
      %(click A href  "u"),
      %(click A href\t\t"u"),
      %(click A "u"  "tip"),
      %(click A "u"  _blank),
      %(click A "u"\t\t_blank),
      %(click A cb  "tip"),
      %(click A call cb()  "tip"),
      %(click A href  "u";B),
      %(click A "u"  "tip";B),
      # An empty quoted run is never a url and never a tooltip. mmdc
      # takes `click A " "` and refuses every one of these.
      %(click A ""),
      %(click A "" "tip"),
      %(click A "u" ""),
      %(click A href ""),
      %(click A href "u" ""),
      %(click A call cb() ""),
      %(click A cb ""),
      # A bare callback name stops where mermaid keeps the character for
      # a shape or an edge. Measured one character at a time: these
      # twelve are refused, `(` is refused with the parens above, and
      # every other printable ASCII character is not.
      "click A cb)x",
      "click A cb<x",
      "click A cb=x",
      "click A cb>x",
      "click A cb@x",
      "click A cb[x",
      "click A cb]x",
      "click A cb^x",
      "click A cb{x",
      "click A cb|x",
      "click A cb}x",
      "click A cb~x"
    ].each do |statement|
      it "refuses #{statement.inspect}" do
        expect(renders?("graph TD\nA\n#{statement}\n")).to be(false)
      end
    end

    [
      %(click A "u"),
      %(click A "u" "tip"),
      "click A \"u\" _blank",
      %(click A "u" "tip" _blank),
      "click A cb",
      "click A callback",
      %(click A cb "tip"),
      "click A http://x",
      %(click A http://x "tip"),
      %(click A href "u"),
      %(click A href "u" "tip"),
      %(click A href "u" _blank),
      # One tab is one gap, and mermaid takes it wherever a space goes.
      %(click A href\t"u"),
      %(click A "u"\t"tip"),
      %(click A "u"\t_blank),
      %(click A cb\t"tip"),
      %(click A call cb()\t"tip"),
      # A quote only opens a url when it comes first. mmdc draws
      # `click A cb"x`, and a bare token carries the rest of the
      # punctuation it does not keep for shapes.
      %(click A cb"x),
      %(click A cb"x "tip"),
      %(click A " "),
      "click A cb,x",
      "click A cb!x",
      "click A cb#x",
      "click A cb.x",
      "click A cb/x",
      "click A cb:x",
      "click A cb?x"
    ].each do |statement|
      it "takes #{statement.inspect}" do
        expect(node_ids("graph TD\nA\n#{statement}\n")).to eq(%w[A])
      end
    end

    it "keeps a callback tooltip on the callback's line" do
      # mmdc refuses a newline before the tooltip, where it takes one
      # inside the parens. `callback_gap` reached across and swallowed the
      # next line into the click; now the tooltip stands on its own line,
      # where a quoted run is not a statement at all.
      expect(renders?(%(graph TD\nA\nclick A call cb()\n"tip"\n))).to be(false)
    end

    # Every action ends at its line, so the orphaned tooltip lands on the
    # next one in each of these.
    [
      %(click A cb),
      %(click A "u"),
      %(click A href "u")
    ].each do |action|
      it "refuses a tooltip on the line after #{action.inspect}" do
        expect(renders?(%(graph TD\nA\n#{action}\n"tip"\n))).to be(false)
      end
    end

    # A `;` still ends the statement after a complete action.
    {
      "a bare callback" => "click A cb;B",
      "a quote inside a bare callback" => %(click A cb"x;B),
      "a quoted url" => %(click A "u";B),
      "a link target" => %(click A "u" _blank;B)
    }.each do |label, statement|
      it "keeps a node after #{label}" do
        expect(node_ids("graph TD\nA\n#{statement}\n")).to eq(%w[A B])
      end
    end
  end

  # A quoted run is not a node id. It used to build a node whose id was a
  # stringified parse tree, so every one of these drew a node called
  # `{string: "tip"@12}` where mmdc draws nothing at all.
  describe "a quoted run where a node id goes" do
    {
      "alone on a line" => %(graph TD\nA\n"tip"\n),
      "after a separator" => %(graph TD;A;"tip"\n),
      "as an edge source" => %(graph TD\n"A" --> B\n),
      "as an edge target" => %(graph TD\nA --> "B"\n),
      "carrying a shape" => %(graph TD\n"A"[x]\n),
      "as a style target" => %(graph TD\nA\nstyle "A" fill:red\n),
      "as a class target" => %(graph TD\nA\nclass "A" foo\n),
      "as a click target" => %(graph TD\nA\nclick "A" "u"\n)
    }.each do |label, source|
      it "is refused #{label}" do
        expect(renders?(source)).to be(false)
      end
    end

    it "is still a label inside a shape" do
      expect(node_ids(%(graph TD\nA["tip"] --- B\n))).to eq(%w[A B])
    end
  end
end
