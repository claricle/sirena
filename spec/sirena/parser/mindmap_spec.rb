# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/mindmap"

RSpec.describe Sirena::Parser::Mindmap do
  let(:parser) { described_class.new }

  def hierarchy(node)
    [node.content, node.children.map { |child| hierarchy(child) }]
  end

  describe "#parse" do
    context "with simple root" do
      it "parses a simple root node" do
        diagram = parser.parse("mindmap\n  root")
        expect(diagram).to be_a(Sirena::Diagram::Mindmap).and(
          have_attributes(root: have_attributes(content: "root", level: 0)),
        )
      end

      it "parses a root with indentation" do
        root = parser.parse("mindmap\n    root").root
        expect(root).to have_attributes(content: "root")
      end
    end

    context "with hierarchical structure" do
      let(:dedented_source) do
        "mindmap\n    " \
          "root\n        " \
          "branch1\n            " \
          "mid1\n                " \
          "leaf1\n        " \
          "branch2\n"
      end

      it "parses a simple hierarchy" do
        source = "mindmap\n    root\n      child1\n      child2"
        children = parser.parse(source).root.children
        expect(children.map(&:content)).to eq(["child1", "child2"])
      end

      it "parses a deeper hierarchy" do
        source = "mindmap\n    root\n      child1\n        leaf1\n      child2"
        root = parser.parse(source).root
        expected = ["root", [["child1", [["leaf1", []]]], ["child2", []]]]
        expect(hierarchy(root)).to eq(expected)
      end

      it "dedents past multiple levels back to a shallower sibling" do
        # 4-space steps throughout (not the 2-space steps the other specs
        # use): this is the shape the fixed-band level calculator mis-banded
        # (relative_indent / 2 skipped a level on every 4-space step), so a
        # regression to that calculator fails here even though the 2-space
        # specs above stay green against it.
        root = parser.parse(dedented_source).root
        expected = ["root", [["branch1", [["mid1", [["leaf1", []]]]]],
                             ["branch2", []]]]
        expect(hierarchy(root)).to eq(expected)
      end

      it "rejects a second node with nothing above it in the stack" do
        # A node that dedents at or below the root's own indent has no
        # ancestor to attach under: Mermaid calls this "Multiple roots are
        # illegal". Without a guard, rebuild_hierarchy silently replaced
        # @root and the first root's whole subtree vanished with no error.
        source = "mindmap\n    root\n  second\n"

        expect { parser.parse(source) }.to raise_error(
          Sirena::Parser::ParseError, /multiple roots/i
        )
      end
    end

    context "with node shapes" do
      let(:commented_round_source) do
        "mindmap\n  root(Root)\n    a(a) %% This is a comment\n    " \
          "b[New Stuff]\n"
      end

      it "parses circle nodes" do
        root = parser.parse("mindmap\n root((the root))").root
        expect(root).to have_attributes(shape: "circle", content: "the root")
      end

      it "parses cloud nodes" do
        root = parser.parse("mindmap\n root)the root(").root
        expect(root).to have_attributes(shape: "cloud", content: "the root")
      end

      it "parses bang nodes" do
        root = parser.parse("mindmap\n root))the root((").root
        expect(root).to have_attributes(shape: "bang", content: "the root")
      end

      it "parses hexagon nodes" do
        root = parser.parse("mindmap\n root{{the root}}").root
        expect(root).to have_attributes(shape: "hexagon", content: "the root")
      end

      it "parses square nodes" do
        root = parser.parse("mindmap\n    root[The root]").root
        expect(root).to have_attributes(shape: "square", content: "The root")
      end

      it "parses a round node (corpus 029, no id prefix)" do
        root = parser.parse("mindmap\n    (root)").root
        expect(root).to have_attributes(shape: "round", content: "root")
      end

      it "parses a round node with an id prefix" do
        root = parser.parse("mindmap\n    root(The root)").root
        expect(root).to have_attributes(shape: "round", content: "The root")
      end

      it "strips exactly one leading newline from multi-line round content " \
         "(corpus 014)" do
        source = "mindmap\n    root(\n      The root\n    )"
        root = parser.parse(source).root
        expect(root).to have_attributes(
          shape: "round", content: "      The root\n    ",
        )
      end

      it "tolerates a trailing %% comment after a round node's close paren " \
         "(corpus 049)" do
        children = parser.parse(commented_round_source).root.children
        expect(children).to match(
          [have_attributes(content: "a", shape: "round"),
           have_attributes(content: "New Stuff")],
        )
      end

      it "drops a whole-line %% comment, not a node (corpus 048)" do
        source = ["mindmap", "  root(Root)", "    a(a)", "",
                  "    %% a comment", "    b[New Stuff]", ""].join("\n")

        diagram = parser.parse(source)
        expect(diagram.root.children.map(&:content)).to eq(["a", "New Stuff"])
      end

      it "strips the quotes from a quoted round node's content" do
        source = 'mindmap
  root("abc")'

        diagram = parser.parse(source)
        expect(diagram.root.content).to eq("abc")
      end

      it "lets a literal close-paren through inside quoted round content" do
        source = 'mindmap
  root("a)b")'

        diagram = parser.parse(source)
        expect(diagram.root.content).to eq("a)b")
      end

      it "preserves comment syntax inside quoted round content" do
        source = 'mindmap
  root("%% keep this")'

        diagram = parser.parse(source)
        expect(diagram.root.content).to eq("%% keep this")
      end

      it "preserves a leading newline inside quoted round content" do
        source = "mindmap\n  root(\"\nfoo\")"

        diagram = parser.parse(source)
        expect(diagram.root.content).to eq("\nfoo")
      end

      it "strips an embedded %% comment-only line from multi-line round " \
         "content" do
        source = "mindmap\n  root(\n    one\n    %% hidden\n    two\n  )"

        diagram = parser.parse(source)
        # The comment line, terminator included, is fully gone -- only the
        # leading "(\n" newline (already covered above) and the two real
        # content lines remain.
        expect(diagram.root.content).to eq("    one\n    two\n  ")
      end

      it "ignores close-parens inside round-node comment lines" do
        source = "mindmap\n  root(\n    one\n    %% hidden )\n    two\n  )"

        diagram = parser.parse(source)
        expect(diagram.root.content).to eq("    one\n    two\n  ")
      end

      it "keeps a %% literally when it doesn't start a real source line" do
        source = "mindmap\n  root(%% keep this)"

        diagram = parser.parse(source)
        # "%%" here sits right after "root(" on the SAME physical line as
        # the node itself, not at the start of a line the way a real
        # embedded comment is -- mermaid only strips a %% comment line that
        # already begins right after a newline, so this one renders
        # literally.
        expect(diagram.root.content).to eq("%% keep this")
      end

      it "does not treat a bare %% line with nothing after it as a comment" do
        source = "mindmap\n  root(\n    one\n    %%\n    two\n  )"

        diagram = parser.parse(source)
        # A comment line needs at least one character after "%%"; a bare
        # "%%" alone is left in place.
        expect(diagram.root.content).to eq("    one\n    %%\n    two\n  ")
      end

      it "strips an embedded %% comment-only line from quoted multi-line " \
         "round content" do
        source = "mindmap\n  root(\"\n    %% keep this\n    foo\")"

        diagram = parser.parse(source)
        # Mermaid's comment strip is a textual pre-pass that runs before
        # quote lexing, so a real embedded comment LINE is stripped even
        # inside a quoted round node's content -- only a %% that shares a
        # physical line with other quoted text (see "preserves comment
        # syntax inside quoted round content" above) survives.
        expect(diagram.root.content).to eq("\n    foo")
      end

      it "strips a quoted %% comment line even when it contains a literal " \
         "quote" do
        source = "mindmap\n  root(\"\n    %% hidden \"\n    foo\")"

        diagram = parser.parse(source)
        # Mermaid strips the whole comment line in a textual pre-pass BEFORE
        # it ever looks for the closing quote, so a stray `"` inside the
        # comment does not end the quoted string early -- matching only
        # `[^"]` per character let it do exactly that, and the whole
        # round_shape alternative fell back to plain-text nodes instead of
        # one node holding "foo".
        expect(diagram.root.content).to eq("\n    foo")
      end

      it "recognizes a non-breaking space as comment indentation" do
        source = "mindmap\n  root(\n %% hidden )\n    foo\n  )"

        diagram = parser.parse(source)
        # Mermaid's comment-strip regex uses JavaScript's `\s`, which
        # matches a no-break space; `[ \t]` alone did not, so the comment
        # line (including its misleading close-paren) was left in place and
        # the extra ")" it contains broke the node open, raising "Multiple
        # roots are illegal".
        expect(diagram.root.content).to eq("    foo\n  ")
      end

      it "strips a CRLF-terminated leading newline from multi-line round " \
         "content" do
        source = "mindmap\r\n  root(\r\n    The root\r\n  )"

        diagram = parser.parse(source)
        # A caller that hands CRLF source straight to this parser (bypassing
        # Source#normalize, which always runs on the real render path) must
        # not see a stray leading "\r" survive in the content.
        expect(diagram.root.content).to eq("    The root\r\n  ")
      end
    end

    context "with icons" do
      it "parses nodes with icons" do
        source = "mindmap\n    root[The root]\n    ::icon(bomb)"
        root = parser.parse(source).root
        expect(root.icon).to eq("bomb")
      end

      it "parses multiple nodes with icons" do
        source = "mindmap\n  root((mindmap))\n    Origins\n      " \
                 "::icon(fa fa-book)"
        child = parser.parse(source).root.children.first
        expect(child.icon).to eq("fa fa-book")
      end
    end

    context "with classes" do
      it "parses nodes with classes" do
        root = parser.parse("mindmap\n    root[The root]\n    :::m-4 p-8").root
        expect(root.classes).to include("m-4", "p-8")
      end

      it "parses nodes with both classes and icons" do
        source = "mindmap\n    root[The root]\n    :::m-4 p-8\n    ::icon(bomb)"
        root = parser.parse(source).root
        expect(root).to have_attributes(
          classes: include("m-4", "p-8"), icon: "bomb",
        )
      end
    end

    context "with complex structures" do
      let(:full_example_source) do
        <<~MERMAID
          mindmap
            root((mindmap))
              Origins
                Long history
                ::icon(fa fa-book)
                Popularisation
                  British popular psychology author Tony Buzan
              Research
                On effectiveness<br/>and features
                On Automatic creation
                  Uses
                      Creative techniques
                      Strategic planning
                      Argument mapping
              Tools
                Pen and paper
                Mermaid
        MERMAID
      end

      it "parses a full example mindmap" do
        root = parser.parse(full_example_source).root
        origins = root.children.first
        values = [root.content, root.shape, root.children.size,
                  origins.content, origins.children.size]
        expect(values).to eq(["mindmap", "circle", 3, "Origins", 2])
      end
    end

    context "with content on the header line (corpus 019)" do
      it "treats text right after the keyword as the root node" do
        root = parser.parse("mindmap-node section-root").root
        expect(root).to have_attributes(content: "-node section-root", level: 0)
      end
    end

    context "with no real newline after the header (corpus 054)" do
      it "takes the whole remainder of the line as the root node" do
        source = 'mindmap\n  root\n    Photograph\n      Waterfall'
        root = parser.parse(source).root
        expect(root).to have_attributes(content: source.sub("mindmap", ""))
      end
    end

    context "with the header keyword boundary" do
      let(:header_comment_sources) do
        ["mindmap %% comment\n  root", "mindmap\t%% comment\n  root"]
      end

      # Keep this: it is the only check on the `match['a-zA-Z0-9_'].absent?`
      # guard in grammars/mindmap.rb's header rule. A whole-file revert of
      # that rule stays green here too (the old rule rejected the same inputs
      # for an unrelated reason), so it becomes the only check once a future
      # change loosens header_tail further and that coincidence stops holding.
      it "rejects an identifier that merely starts with mindmap" do
        attempts = %w[mindmapfoo mindmap_foo mindmap1].map do |source|
          proc { parser.parse(source) }
        end
        expect(attempts).to all(raise_error(Sirena::Parser::ParseError))
      end

      it "still accepts a space or hyphen right after the keyword" do
        contents = ["mindmap foo", "mindmap-foo"].map do |source|
          parser.parse(source).root.content
        end
        expect(contents).to eq(["foo", "-foo"])
      end

      it "treats a tab after the keyword as an inert separator" do
        diagram = parser.parse("mindmap\troot")
        expect(diagram.root.content).to eq("root")
      end

      it "discards a comment trailing the header and reads root from the " \
         "next line" do
        contents = header_comment_sources.map do |source|
          parser.parse(source).root.content
        end
        expect(contents).to eq(["root", "root"])
      end

      it "still finds the root when two or more separators follow the " \
         "keyword" do
        root = parser.parse("mindmap  root\n    child").root
        expect(root).to have_attributes(
          content: "root", children: match([have_attributes(content: "child")]),
        )
      end

      it "discards a comment even when several separators precede it" do
        diagram = parser.parse("mindmap  %% comment\n  root")
        expect(diagram).to have_attributes(
          root: have_attributes(content: "root"),
          nodes: have_attributes(size: 1),
        )
      end

      it "does not leave a trailing separator inside the root's label" do
        diagram = parser.parse("mindmap \tfoo")

        expect(diagram.root.content).to eq("foo")
      end

      it "counts the separator after the keyword as the inline root's " \
         "indent, " \
         "so a later line at the same indent is a second root" do
        # Mermaid's own lexer turns the run of spaces right after "mindmap"
        # into the root's SPACELIST token, and mindmapDb.addNode sets
        # baseLevel from that token's length -- so a later line at that same
        # raw indent is a SIBLING of the root, not its child, and mermaid
        # rejects it ("There can be only one root."). Discarding that
        # whitespace instead of counting it would make the second line look
        # shallower than it is and nest it under the root wrongly.
        #
        # Keep this: it is the only check that header_tail's `str('')`
        # fallback (leave the separator for node_line to capture as indent)
        # doesn't get replaced by something that swallows it instead --
        # verified by swapping that one alternative for an eager
        # `match[' \t'].repeat`, which goes red on its own. A whole-file
        # revert to before inline-root support existed stays green here too
        # (no inline root means a different parse failure for an unrelated
        # reason).
        expect { parser.parse("mindmap  root\n  child") }
          .to raise_error(Sirena::Parser::ParseError, /[Mm]ultiple roots/)
      end
    end
  end

  describe "#parse a header with no nodes" do
    it "has no root" do
      expect(parser.parse("mindmap\n").root).to be_nil
    end

    it "has no nodes" do
      expect(parser.parse("mindmap\n").nodes).to be_empty
    end
  end
end
