# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/mindmap"

RSpec.describe Sirena::Parser::Mindmap do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with simple root" do
      it "parses a simple root node" do
        source = <<~MERMAID
          mindmap
            root
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Mindmap)
        expect(diagram.root).not_to be_nil
        expect(diagram.root.content).to eq("root")
        expect(diagram.root.level).to eq(0)
      end

      it "parses a root with indentation" do
        source = <<~MERMAID
          mindmap
              root
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root).not_to be_nil
        expect(diagram.root.content).to eq("root")
      end
    end

    context "with hierarchical structure" do
      it "parses a simple hierarchy" do
        source = <<~MERMAID
          mindmap
              root
                child1
                child2
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.children.size).to eq(2)
        expect(diagram.root.children.map(&:content)).to eq(["child1", "child2"])
      end

      it "parses a deeper hierarchy" do
        source = <<~MERMAID
          mindmap
              root
                child1
                  leaf1
                child2
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.children.size).to eq(2)
        expect(diagram.root.children.first.children.size).to eq(1)
        expect(diagram.root.children.first.children.first.content).to eq("leaf1")
      end

      it "dedents past multiple levels back to a shallower sibling" do
        # 4-space steps throughout (not the 2-space steps the other specs
        # use): this is the shape the fixed-band level calculator mis-banded
        # (relative_indent / 2 skipped a level on every 4-space step), so a
        # regression to that calculator fails here even though the 2-space
        # specs above stay green against it.
        source = "mindmap\n    " \
                 "root\n        " \
                 "branch1\n            " \
                 "mid1\n                " \
                 "leaf1\n        " \
                 "branch2\n"

        diagram = parser.parse(source)
        expect(diagram.root.children.map(&:content)).to eq(["branch1", "branch2"])

        branch1 = diagram.root.children.first
        expect(branch1.children.size).to eq(1)
        expect(branch1.children.first.content).to eq("mid1")
        expect(branch1.children.first.children.map(&:content)).to eq(["leaf1"])

        branch2 = diagram.root.children.last
        expect(branch2.children).to be_empty
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
      it "parses circle nodes" do
        source = <<~MERMAID
          mindmap
           root((the root))
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("circle")
        expect(diagram.root.content).to eq("the root")
      end

      it "parses cloud nodes" do
        source = <<~MERMAID
          mindmap
           root)the root(
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("cloud")
        expect(diagram.root.content).to eq("the root")
      end

      it "parses bang nodes" do
        source = <<~MERMAID
          mindmap
           root))the root((
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("bang")
        expect(diagram.root.content).to eq("the root")
      end

      it "parses hexagon nodes" do
        source = <<~MERMAID
          mindmap
           root{{the root}}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("hexagon")
        expect(diagram.root.content).to eq("the root")
      end

      it "parses square nodes" do
        source = <<~MERMAID
          mindmap
              root[The root]
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.shape).to eq("square")
        expect(diagram.root.content).to eq("The root")
      end
    end

    context "with icons" do
      it "parses nodes with icons" do
        source = <<~MERMAID
          mindmap
              root[The root]
              ::icon(bomb)
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.icon).to eq("bomb")
      end

      it "parses multiple nodes with icons" do
        source = <<~MERMAID
          mindmap
            root((mindmap))
              Origins
                ::icon(fa fa-book)
        MERMAID

        diagram = parser.parse(source)
        child = diagram.root.children.first
        expect(child.icon).to eq("fa fa-book")
      end
    end

    context "with classes" do
      it "parses nodes with classes" do
        source = <<~MERMAID
          mindmap
              root[The root]
              :::m-4 p-8
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.classes).to include("m-4", "p-8")
      end

      it "parses nodes with both classes and icons" do
        source = <<~MERMAID
          mindmap
              root[The root]
              :::m-4 p-8
              ::icon(bomb)
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root.classes).to include("m-4", "p-8")
        expect(diagram.root.icon).to eq("bomb")
      end
    end

    context "with complex structures" do
      it "parses a full example mindmap" do
        source = <<~MERMAID
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

        diagram = parser.parse(source)
        expect(diagram.root).not_to be_nil
        expect(diagram.root.content).to eq("mindmap")
        expect(diagram.root.shape).to eq("circle")
        expect(diagram.root.children.size).to eq(3)

        origins = diagram.root.children[0]
        expect(origins.content).to eq("Origins")
        expect(origins.children.size).to eq(2)
      end
    end

    context "with content on the header line (corpus 019)" do
      it "treats text right after the keyword as the root node" do
        source = "mindmap-node section-root"

        diagram = parser.parse(source)
        expect(diagram.root).not_to be_nil
        expect(diagram.root.content).to eq("-node section-root")
        expect(diagram.root.level).to eq(0)
      end
    end

    context "with no real newline after the header (corpus 054)" do
      it "takes the whole remainder of the line as the root node" do
        source = 'mindmap\n  root\n    Photograph\n      Waterfall'

        diagram = parser.parse(source)
        expect(diagram.root).not_to be_nil
        expect(diagram.root.content).to eq(source.sub("mindmap", ""))
      end
    end

    context "with the header keyword boundary" do
      # Keep this: it is the only check on the `match['a-zA-Z0-9_'].absent?`
      # guard in grammars/mindmap.rb's header rule. A whole-file revert of
      # that rule stays green here too (the old rule rejected the same inputs
      # for an unrelated reason), so it becomes the only check once a future
      # change loosens header_tail further and that coincidence stops holding.
      it "rejects an identifier that merely starts with mindmap" do
        %w[mindmapfoo mindmap_foo mindmap1].each do |source|
          expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
        end
      end

      it "still accepts a space or hyphen right after the keyword" do
        diagram = parser.parse("mindmap foo")
        expect(diagram.root.content).to eq("foo")

        diagram = parser.parse("mindmap-foo")
        expect(diagram.root.content).to eq("-foo")
      end

      it "treats a tab after the keyword as an inert separator" do
        diagram = parser.parse("mindmap\troot")
        expect(diagram.root.content).to eq("root")
      end

      it "discards a comment trailing the header and reads root from the next line" do
        [
          "mindmap %% comment\n  root",
          "mindmap\t%% comment\n  root"
        ].each do |source|
          diagram = parser.parse(source)
          expect(diagram.root.content).to eq("root")
        end
      end

      it "still finds the root when two or more separators follow the keyword" do
        diagram = parser.parse("mindmap  root\n    child")

        expect(diagram.root.content).to eq("root")
        expect(diagram.root.children.map(&:content)).to eq(["child"])
      end

      it "discards a comment even when several separators precede it" do
        diagram = parser.parse("mindmap  %% comment\n  root")

        expect(diagram.root.content).to eq("root")
        expect(diagram.nodes.size).to eq(1)
      end

      it "does not leave a trailing separator inside the root's label" do
        diagram = parser.parse("mindmap \tfoo")

        expect(diagram.root.content).to eq("foo")
      end

      it "counts the separator after the keyword as the inline root's indent, " \
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
end