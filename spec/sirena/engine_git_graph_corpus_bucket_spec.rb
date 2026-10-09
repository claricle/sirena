# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

module GitGraphBucketHelpers
  CORPUS = File.expand_path("../mermaid/git", __dir__)
  ANCHOR_SHARE = { "start" => 0, "middle" => 0.5, "end" => 1 }.freeze

  # Source builders, also called from the describe bodies below.
  module_function

  def tagged_commit(direction, tag)
    "gitGraph #{direction}:\n commit id: \"c\" tag: \"#{tag}\"\n"
  end

  def commit_chain(direction, ids)
    ["gitGraph #{direction}:\n", *ids.map { |id| " commit id: \"#{id}\"\n" }]
      .join
  end

  def long_branch(direction, name)
    "gitGraph #{direction}:\n commit\n branch \"#{name}\"\n " \
      "checkout \"#{name}\"\n commit\n"
  end

  def branch_with_id(direction, id)
    "gitGraph #{direction}:\n commit\n branch develop\n " \
      "checkout develop\n commit id: \"#{id}\"\n"
  end

  def corpus_case(number)
    Dir.glob(File.join(CORPUS, format("%03d_*.mmd", number))).fetch(0)
  end

  def parse(source)
    Sirena::Parser::GitGraph.new.parse(source)
  end

  def parse_statement(template, statement)
    parse(format(template, statement))
  end

  def layout_for(source)
    Sirena::Layout::GitGraph.new.to_graph(parse(source))
  end

  def render_svg(source)
    REXML::Document.new(Sirena::Engine.new.render(source))
  end

  def circle_centers(svg)
    REXML::XPath.match(svg, "//circle").map do |c|
      [c.attributes["cx"].to_f, c.attributes["cy"].to_f]
    end
  end

  def texts(svg)
    REXML::XPath.match(svg, "//text").map(&:text)
  end

  def number(element, name)
    element.attributes[name].to_f
  end

  # Left and right edge of each label, by TextMeasurement's per-glyph width.
  # The renderer sizes by a wider hint, so a label inside the box here is
  # inside it by a margin; the real-width table below is the exact check.
  def label_edges(svg)
    REXML::XPath.match(svg, "//text").map do |t|
      width = label_width(t)
      share = ANCHOR_SHARE.fetch(t.attributes["text-anchor"])
      left = number(t, "x") - (width * share)
      [t.text, left, left + width]
    end
  end

  def label_width(text)
    Sirena::TextMeasurement.measure(
      text.text, font_size: number(text, "font-size")
    )[:width]
  end

  def widest_text(svg)
    REXML::XPath.match(svg, "//text").max_by { |t| t.text.length }
  end

  def left_edge(text, width)
    x = number(text, "x")
    text.attributes["text-anchor"] == "end" ? x - width : x
  end

  def text_named(svg, content)
    REXML::XPath.match(svg, "//text").find { |t| t.text == content }
  end
end

# The gitGraph corpus cases that used to fail at parse, one group per
# root construct. Every case is accepted by mmdc.
RSpec.describe Sirena::Engine do
  include GitGraphBucketHelpers

  {
    "gitGraph BT:" => [*37..50, 52, 69],
    "commit with a message" => [84, 89, 90, 91, 92],
    "quoted branch names" => [95],
    "accTitle and accDescr" => [127, 128],
  }.each do |bucket, numbers|
    describe bucket do
      numbers.each do |number|
        it "renders corpus case git/#{format('%03d', number)}" do
          svg = render_svg(File.read(corpus_case(number)))

          expect(REXML::XPath.match(svg, "//circle")).not_to be_empty
        end
      end
    end
  end

  describe "an empty diagram" do
    {
      "LR" => [240.0, 260.0],
      "TB" => [260.0, 240.0],
      "BT" => [260.0, 240.0],
    }.each do |direction, size|
      it "renders #{direction} at #{size.join('x')} with nothing drawn" do
        svg = render_svg("gitGraph #{direction}:\n")
        root = svg.root.attributes
        drawn = REXML::XPath.match(svg, "//text|//circle")

        expect([root["width"].to_f, root["height"].to_f, drawn])
          .to eq([*size, []])
      end
    end
  end

  describe "BT direction" do
    let(:source) { commit_chain("BT", %w[first second third]) }
    let(:svg) { render_svg(source) }
    let(:centers) { circle_centers(svg) }

    it "draws the first commit at the bottom and later ones above it" do
      ys = centers.map(&:last)

      expect(ys).to eq(ys.uniq.sort.reverse)
    end

    it "keeps every commit in one column" do
      expect(centers.map(&:first).uniq.size).to eq(1)
    end

    it "puts a second branch in its own column" do
      branched = "#{source} branch dev\n checkout dev\n commit id: \"d\"\n"
      second = render_svg(branched)

      expect(circle_centers(second).map(&:first).uniq.size).to eq(2)
    end

    it "orders time the opposite way to TB" do
      top_down = circle_centers(render_svg(source.sub("BT", "TB"))).map(&:last)
      bottom_up = centers.map(&:last)

      expect([bottom_up.first > bottom_up.last, top_down.first < top_down.last])
        .to eq([true, true])
    end

    it "puts a commit label to the right of the commit" do
      expect(number(text_named(svg, "first"), "x")).to be > centers.first.first
    end

    it "puts a commit label level with the commit" do
      label_y = number(text_named(svg, "first"), "y")

      expect(label_y).to be_within(5).of(centers.first.last)
    end

    it "puts the branch name past the last commit" do
      expect(number(text_named(svg, "main"), "y")).to be < centers.last.last
    end

    it "puts a tag left of the commit" do
      tagged = render_svg(tagged_commit("BT", "v1"))

      expect(number(text_named(tagged, "v1"), "x"))
        .to be < circle_centers(tagged).first.first
    end

    it "puts the commit id on the opposite side of the commit from its tag" do
      tagged = render_svg(tagged_commit("BT", "v1"))

      expect(number(text_named(tagged, "c"), "x"))
        .to be > circle_centers(tagged).first.first
    end

    it "puts the branch name below the last commit for TB" do
      tb = render_svg(source.sub("BT", "TB"))

      expect(number(text_named(tb, "main"), "y"))
        .to be > circle_centers(tb).last.last + 10
    end

    it "sizes the document with commits along the vertical axis" do
      expect(number(svg.root, "height")).to be > number(svg.root, "width")
    end

    it "allows a space between the direction and the colon" do
      spaced = render_svg("gitGraph BT :\n commit\n commit\n")
      ys = circle_centers(spaced).map(&:last)

      expect(ys).to eq(ys.uniq.sort.reverse)
    end

    it "leaves LR laid out left to right, one column per commit" do
      xs = circle_centers(render_svg(source.sub("BT:", "LR:"))).map(&:first)

      expect(xs).to eq(xs.uniq.sort)
    end

    it "sizes an LR document with commits along the horizontal axis" do
      root = render_svg(source.sub("BT:", "LR:")).root

      expect(number(root, "width")).to be > number(root, "height")
    end
  end

  describe "commit spacing" do
    { "LR" => :first, "TB" => :last, "BT" => :last }.each do |direction, axis|
      it "puts commits 80px apart along the time axis, #{direction}" do
        centers = circle_centers(render_svg(commit_chain(direction, %w[a b c])))
        gaps = centers.map(&axis).each_cons(2).map { |a, b| (a - b).abs }

        expect(gaps).to eq([80, 80])
      end
    end
  end

  describe "label extents" do
    {
      "an id right of the last lane, TB" =>
        GitGraphBucketHelpers.branch_with_id("TB", "feature-login-form"),
      "an id right of the last lane, BT" =>
        GitGraphBucketHelpers.branch_with_id("BT", "feature-login-form"),
      "a tag left of the first lane, TB" =>
        GitGraphBucketHelpers.tagged_commit("TB", "t" * 40),
      "a tag left of the first lane, BT" =>
        GitGraphBucketHelpers.tagged_commit("BT", "t" * 40),
      "a long branch name, TB" =>
        GitGraphBucketHelpers.long_branch("TB", "a-very-long-branch-name-yes"),
      "a long id under the last commit, LR" =>
        "gitGraph LR:\n commit id: \"#{'x' * 60}\"\n",
      "a long branch name past the last commit, LR" =>
        GitGraphBucketHelpers.long_branch("LR", "b" * 40),
    }.each do |label, source|
      context "with #{label}" do
        let(:svg) { render_svg(source) }
        let(:width) { number(svg.root, "width") }

        it "keeps the viewBox the size of the document" do
          expect(svg.root.attributes["viewBox"])
            .to eq("0 0 #{width} #{number(svg.root, 'height')}")
        end

        it "keeps every label inside the viewBox" do
          outside = label_edges(svg).select do |_, left, right|
            left < 0 || right > width
          end

          expect(outside).to eq([])
        end
      end
    end

    it "sizes a label by what is drawn, not by dropped control characters" do
      plain = "gitGraph TB:\n commit\n branch \"x\"\n checkout \"x\"\n commit\n"
      escaped = plain.gsub('"x"', "\"x#{'\\b' * 100}\"")

      expect(render_svg(escaped).root.attributes["width"])
        .to eq(render_svg(plain).root.attributes["width"])
    end

    # Advance widths of the drawn text in real Arial / Arial Bold at 12px,
    # summed from the fonts' hmtx tables with fontTools, so no estimator of
    # this gem's is in the oracle. The CJK row is 60 Han at 12.25px each,
    # from Chrome's getBBox of 80 Han in this gem's own flowchart label
    # (986.40625 less two `|`), as Arial has no Han glyphs.
    {
      "a tag in TB" => [
        "gitGraph TB:\n commit tag: \"HOTFIX-1234-PRODUCTION-ROLLBACK\"\n " \
        "commit\n",
        230.67,
      ],
      "a tag in BT" => [
        "gitGraph BT:\n commit tag: \"HOTFIX-1234-PRODUCTION-ROLLBACK\"\n " \
        "commit\n",
        230.67,
      ],
      "an id in TB" => [
        "gitGraph TB:\n commit id: \"Merge pull request #1234 from " \
        "Org/Feature\"\n",
        231.45,
      ],
      "a CJK tag in TB" => [
        "gitGraph TB:\n commit tag: \"#{"\u{4E2D}" * 60}\"\n commit\n",
        735.0,
      ],
    }.each do |label, (source, real_width)|
      it "keeps #{label} inside the viewBox at its real width" do
        svg = render_svg(source)
        left = left_edge(widest_text(svg), real_width)

        expect([left >= 0, left + real_width <= number(svg.root, "width")])
          .to eq([true, true])
      end
    end

    it "leaves a tag the measured width plus 20 percent headroom of room" do
      tag = "HOTFIX-1234-PRODUCTION-ROLLBACK"
      drawn = text_named(render_svg(tagged_commit("TB", tag)), tag)
      size = number(drawn, "font-size")
      measured = Sirena::TextMeasurement.measure(tag, font_size: size)[:width]

      expect(number(drawn, "x")).to be_within(0.01).of(measured * 1.2)
    end

    it "leaves the box alone when every label fits" do
      source = commit_chain("TB", %w[a b])

      expect(number(render_svg(source).root, "width"))
        .to eq(layout_for(source).width)
    end
  end

  describe "a subclass of the renderer" do
    let(:layout) { layout_for(commit_chain("TB", %w[a b])) }
    let(:spilling) { layout_for(tagged_commit("TB", "t" * 40)) }
    let(:subclass) do
      Class.new(Sirena::Renderer::GitGraph) do
        attr_reader :label_calls

        protected

        def create_document_from_layout(layout)
          super.tap { |doc| doc.view_box = "-5 -5 999 888" }
        end

        def render_labels(layout, svg)
          @label_calls = @label_calls.to_i + 1
          super
        end
      end
    end

    context "with a document hook that adds an element" do
      let(:marker) do
        Class.new(subclass) do
          protected

          def create_document_from_layout(layout)
            super.tap do |doc|
              circle = Sirena::Svg::Circle.new
              circle.id = "marker"
              doc.add_element(circle)
            end
          end
        end
      end

      it "keeps what its own document hook added when a label spills left" do
        expect(marker.new.render(spilling).to_xml.scan('id="marker"').size)
          .to eq(1)
      end
    end

    it "keeps the origin of its own viewBox when a label spills left" do
      doc = subclass.new.render(spilling)

      expect(doc.view_box).to eq("-5 -5 999 888")
    end

    context "with a subclass that adds no labels" do
      let(:silent) do
        Class.new(Sirena::Renderer::GitGraph) do
          protected

          def render_labels(_layout, _svg); end
        end
      end

      it "draws a layout whose subclass adds no labels" do
        expect(silent.new.render(layout).width).to eq(layout.width)
      end
    end

    context "with a document hook that clears the viewBox" do
      let(:bare) do
        Class.new(subclass) do
          protected

          def create_document_from_layout(layout)
            super.tap { |doc| doc.view_box = nil }
          end
        end
      end

      it "adds no viewBox when a label spills and the hook cleared it" do
        expect(bare.new.render(spilling).view_box).to be_nil
      end
    end

    context "with a document hook that adds a wide text" do
      let(:wide) do
        Class.new(subclass) do
          protected

          def create_document_from_layout(layout)
            doc = super
            doc.add_element(wide_text)
            doc
          end

          def wide_text
            Sirena::Svg::Text.new.tap do |t|
              t.x = 10
              t.text_anchor = "end"
              t.font_size = "10"
              t.content = ["h" * 40]
            end
          end
        end
      end

      it "does not size the box by text its own document hook added" do
        expect(wide.new.render(layout).width)
          .to eq(subclass.new.render(layout).width)
      end
    end

    context "when a label spills only to the right" do
      it "widens the box" do
        right_only = layout_for(long_branch("LR", "b" * 60))
        short = layout_for(long_branch("LR", "b"))

        expect(subclass.new.render(right_only).width)
          .to be > short.width
      end

      it "sees render_labels once" do
        renderer = subclass.new
        renderer.render(layout_for(long_branch("LR", "b" * 60)))

        expect(renderer.label_calls).to eq(1)
      end
    end

    context "when every label fits" do
      let(:renderer) { subclass.new }
      let!(:doc) { renderer.render(layout) }

      it "sees render_labels once" do
        expect(renderer.label_calls).to eq(1)
      end

      it "keeps its own viewBox" do
        expect(doc.view_box).to eq("-5 -5 999 888")
      end
    end
  end

  describe "commit messages" do
    it "reads an escaped quote inside a message as a quote" do
      diagram = parse("gitGraph\n commit \"say \\\"hi\\\"\" id: \"c\"\n")

      expect(diagram.commits.first.message).to eq('say "hi"')
    end

    # Expected values are what mermaid's own parser returns for the same source.
    {
      '\\n' => "\n", '\\t' => "\t", '\\r' => "\r", '\\b' => "\b",
      '\\f' => "\f", '\\v' => "\v", '\\0' => "\0", "\\\\" => "\\",
      '\\x' => "x", '\\/' => "/"
    }.each do |escape, expected|
      it "reads #{escape} inside a message as #{expected.inspect}" do
        diagram = parse("gitGraph\n commit msg: \"p#{escape}q\"\n")

        expect(diagram.commits.first.message).to eq("p#{expected}q")
      end
    end

    # Mermaid's lexer rejects a backslash before any of these, quoted either
    # way.
    {
      "LF" => "\n", "CR" => "\r", "CRLF" => "\r\n",
      "LS" => "\u2028", "PS" => "\u2029"
    }.to_a.product(%w[" ']).each do |(name, line_break), quote|
      it "refuses a backslash before #{name} in a #{quote}-quoted message" do
        source = "gitGraph\n commit msg: #{quote}a\\#{line_break}b#{quote}\n"

        expect { parse(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "keeps an unescaped line break inside a message" do
      diagram = parse("gitGraph\n commit msg: \"a\nb\"\n")

      expect(diagram.commits.first.message).to eq("a\nb")
    end

    it "refuses a backslash before a line break in a branch name" do
      source = "gitGraph\n commit\n branch \"a\\\nb\"\n"

      expect { parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "reads escapes the same in a single-quoted message" do
      diagram = parse("gitGraph\n commit msg: 'p\\'q\\nr'\n")

      expect(diagram.commits.first.message).to eq("p'q\nr")
    end

    it "accepts an empty message" do
      diagram = parse("gitGraph\n commit \"\"\n")

      expect(diagram.commits.first.message).to eq("")
    end

    it "accepts several spaces before the options" do
      diagram = parse("gitGraph\n commit   id: \"c\"\n")

      expect(diagram.commits.first.id).to eq("c")
    end

    it "reads a bare quoted message and a msg: option into the model" do
      diagram = parse(
        "gitGraph\n commit \"plain\"\n commit msg: \"keyed\" id: \"k\"\n",
      )

      expect(diagram.commits.map(&:message)).to eq(%w[plain keyed])
    end

    {
      "double-quoted, no space" => ["commit\"m\"", "m"],
      "single-quoted, no space" => ["commit'm'", "m"],
      "no space before a second option" => ["commit\"m\"id: \"k\"", "m"],
    }.each do |name, (statement, message)|
      it "reads a message right after the keyword: #{name}" do
        diagram = parse("gitGraph\n #{statement}\n")

        expect(diagram.commits.first.message).to eq(message)
      end
    end

    it "still needs a space between the keyword and an unquoted option" do
      source = "gitGraph\n commitid: \"c\"\n"

      expect { parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "keeps the id given next to the message" do
      svg = render_svg("gitGraph\n commit \"plain\" id: \"abc\"\n")

      expect(texts(svg)).to include("abc")
    end
  end

  describe "quoted branch names" do
    context "with a quoted name for the bare one" do
      let(:diagram) do
        parse("gitGraph\n commit\n branch \"dev\"\n checkout dev\n commit\n")
      end

      it "puts the commit on the bare branch" do
        expect(diagram.commits.last.branch_name).to eq("dev")
      end

      it "declares the branch under the bare name" do
        expect(diagram.branches.map(&:name)).to include("dev")
      end
    end

    context "with an escaped quote in a name for branch, checkout and merge" do
      let(:diagram) do
        parse(
          "gitGraph\n commit\n branch \"a\\\"b\"\n checkout \"a\\\"b\"\n " \
          "commit\n checkout main\n merge \"a\\\"b\"\n",
        )
      end

      it "reads it in branch" do
        expect(diagram.branches.map(&:name)).to include('a"b')
      end

      it "reads it in checkout" do
        expect(diagram.commits[1].branch_name).to eq('a"b')
      end

      it "reads it in merge" do
        expect(diagram.commits.last.merge_branch).to eq('a"b')
      end
    end

    it "reads an escaped backslash in a name as one backslash" do
      diagram = parse("gitGraph\n commit\n branch \"a\\\\b\"\n")

      expect(diagram.branches.map(&:name)).to include("a\\b")
    end

    it "closes a name that ends in an escaped backslash" do
      diagram = parse(
        "gitGraph\n commit\n branch \"a\\\\\"\n checkout \"a\\\\\"\n commit\n",
      )

      expect(diagram.commits.last.branch_name).to eq("a\\")
    end

    it "closes a single-quoted name that ends in an escaped backslash" do
      diagram = parse(
        "gitGraph\n commit\n branch 'a\\\\'\n checkout 'a\\\\'\n commit\n",
      )

      expect(diagram.commits.last.branch_name).to eq("a\\")
    end

    it "reads an escaped single quote in a single-quoted name" do
      diagram = parse("gitGraph\n commit\n branch 'a\\'b'\n")

      expect(diagram.branches.map(&:name)).to include("a'b")
    end

    it "accepts single quotes around a name" do
      diagram = parse(
        "gitGraph\n commit\n branch 'my branch'\n " \
        "checkout 'my branch'\n commit\n",
      )

      expect(diagram.commits.last.branch_name).to eq("my branch")
    end

    gaps = {
      "no space" => "", "one space" => " ", "several spaces" => "   ",
      "a tab" => "\t"
    }
    two_branches = "gitGraph\n commit\n branch \"my branch\"\n " \
                   "branch dev\n %s\n"

    {
      "branch" => "gitGraph\n commit\n %s\n",
      "checkout" => two_branches,
      "switch" => two_branches,
      "merge" => two_branches,
    }.each do |keyword, template|
      gaps.each do |gap_name, gap|
        it "accepts #{gap_name} between #{keyword} and a quoted name" do
          diagram = parse_statement(template, "#{keyword}#{gap}\"my branch\"")

          expect(diagram.branches.map(&:name)).to include("my branch")
        end
      end

      it "accepts several spaces between #{keyword} and a bare name" do
        diagram = parse_statement(template, "#{keyword}   dev")

        expect(diagram.branches.map(&:name)).to include("dev")
      end

      it "still needs a space between #{keyword} and a bare name" do
        expect { parse_statement(template, "#{keyword}dev") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "keeps spaces inside a quoted name" do
      diagram = parse(
        "gitGraph\n commit\n branch \"my branch\"\n " \
        "switch \"my branch\"\n commit\n",
      )

      expect(diagram.commits.last.branch_name).to eq("my branch")
    end
  end

  describe "accessibility statements" do
    it "accepts a brace block on the line after accDescr" do
      diagram = parse("gitGraph\naccDescr\n{hello}\ncommit\n")

      expect(diagram.acc_description).to eq("hello")
    end

    it "reads empty directives as empty text" do
      diagram = parse("gitGraph\n accTitle:\n accDescr {}\n commit\n")

      expect([diagram.acc_title, diagram.acc_description]).to eq(["", ""])
    end

    context "with accTitle and a multi-line accDescr" do
      let(:diagram) do
        parse(
          "gitGraph\n accTitle: A title \n accDescr {\n line one\n " \
          "line two\n }\n commit\n",
        )
      end

      it "stores accTitle" do
        expect(diagram.acc_title).to eq("A title")
      end

      it "stores the accDescr lines" do
        expect(diagram.acc_description).to eq("line one\nline two")
      end
    end
  end
end
