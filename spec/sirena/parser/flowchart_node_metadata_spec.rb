# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  def node_for(source)
    described_class.new.parse(source).nodes.last
  end

  describe "@{ } node metadata" do
    it "sets the shape" do
      expect(node_for("graph TD\nD@{ shape: rounded }\n").shape).to eq("rounded")
    end

    it "sets the label" do
      expect(node_for(%(graph TD\nD@{ label: "for D" }\n)).label).to eq("for D")
    end

    it "takes both, comma separated" do
      node = node_for(%(graph TD\nD@{ shape: hexagon, label: "DD" }\n))

      expect(node.shape).to eq("hexagon")
      expect(node.label).to eq("DD")
    end

    # Whitespace around the braces is free-form in mermaid. The space after
    # the colon is not: without it the key is unknown and ignored, which has
    # its own example below.
    {
      "space before the brace only" => "D@{ shape: rounded}",
      "space after the value" => "D@{ shape: rounded }",
      "generous spacing" => "D@{       shape: rounded         }",
      "space before the colon" => "D@{ shape : rounded }"
    }.each do |label, statement|
      it "accepts #{label}" do
        expect(node_for("graph TD\n#{statement}\n").shape).to eq("rounded")
      end
    end

    it "takes a single-quoted value" do
      # Non-default on purpose: asserting `rect` passes even when the whole
      # metadata block is dropped on the floor.
      expect(node_for("graph TD\nD@{ shape: 'rounded' }\n").shape)
        .to eq("rounded")
    end

    it "keeps whitespace inside a quoted value" do
      # YAML strips the space around an unquoted value, so `label: padded  `
      # is "padded" in mmdc and here. Quoting is the only way to keep it.
      expect(node_for(%(graph TD\nD@{ label: " padded " }\n)).label)
        .to eq(" padded ")
    end

    it "strips the space around an unquoted value" do
      expect(node_for("graph TD\nD@{ label: padded  }\n").label)
        .to eq("padded")
    end

    it "wins over the bracket form when a node carries both" do
      node = node_for(%(graph TD\nD[bracket]@{ shape: hexagon, label: "meta" }\n))

      expect(node.shape).to eq("hexagon")
      expect(node.label).to eq("meta")
    end

    it "works on a node inside an edge chain" do
      expect(node_for(%(graph TD\nA --> C@{ label: "for c" }\n)).label)
        .to eq("for c")
    end
  end

  describe "a shape name mermaid does not know" do
    # mmdc rejects an unknown shape rather than falling back, and two
    # corpus cases are its own negative tests for exactly this. Accepting
    # anything here would render sources mermaid refuses.
    it "raises rather than falling back to a rectangle" do
      expect { node_for("graph TD\nD@{ shape: nope }\n") }
        .to raise_error(Sirena::Parser::ParseError, /No such shape: nope/)
    end

    it "raises for an internal-only name" do
      expect { node_for("graph TD\nD@{ shape: rect_left_inv_arrow }\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    # These three read like ordinary names and mermaid rejects all of them,
    # which is why the accepted set is generated from mmdc rather than
    # written out by hand.
    %w[lined-proc multi-process multi-rect].each do |name|
      it "raises for #{name}, which mermaid does not know" do
        expect { node_for("graph TD\nD@{ shape: #{name} }\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "shape names that collapse" do
    # Sirena draws five distinct shapes where mermaid names about seventy,
    # so many names map onto the same one. That is a renderer gap, not a
    # parsing one, and it is recorded rather than hidden.
    {
      "proc" => "rect", "rectangle" => "rect", "notch-rect" => "rect",
      "event" => "rounded", "terminal" => "stadium", "pill" => "stadium",
      "db" => "cylindrical", "database" => "cylindrical",
      "question" => "rhombus", "decision" => "rhombus",
      "in-out" => "parallelogram", "lean-r" => "parallelogram",
      "out-in" => "parallelogram_alt", "junction" => "double_circle",
      "circ" => "circle", "hex" => "hexagon"
    }.each do |name, expected|
      it "maps #{name} to #{expected}" do
        expect(node_for("graph TD\nD@{ shape: #{name} }\n").shape)
          .to eq(expected)
      end
    end
  end

  describe "mapping shapes mermaid draws identically" do
    it "gives junction and filled-circle the same shape" do
      # mermaid draws these as one shape; mapping junction to a rectangle
      # made them visibly different here.
      expect(node_for("graph TD\nD@{ shape: junction }\n").shape)
        .to eq(node_for("graph TD\nD@{ shape: filled-circle }\n").shape)
    end

    it "gives in-out and lean-r the same shape" do
      expect(node_for("graph TD\nD@{ shape: in-out }\n").shape)
        .to eq(node_for("graph TD\nD@{ shape: lean-r }\n").shape)
    end
  end

  describe "the body is YAML, because that is what mermaid parses it as" do
    it "takes a multiline block body with no commas" do
      source = "graph TD\nA@{\n  shape: rounded\n  label: \"x\"\n}\n"
      node = node_for(source)

      expect([node.shape, node.label]).to eq(%w[rounded x])
    end

    it "refuses commas in a multiline body" do
      # Single line is a flow mapping and multiline is block YAML. Commas
      # belong to the first and not the second, which is why the body is
      # handed to YAML rather than picked apart by the grammar.
      source = "graph TD\nA@{\n  shape: rect,\n  label: \"x\"\n}\n"

      expect { node_for(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses a multiline body with no entries" do
      expect { node_for("graph TD\nA@{\n}\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "keeps a brace inside a quoted value" do
      expect(node_for(%(graph TD\nA@{ label: "a}b" }\n)).label).to eq("a}b")
    end

    it "ignores a key with no space after its colon, as mermaid does" do
      # mmdc accepts the source and renders a plain rectangle: `shape:rounded`
      # is one unknown key there, not a shape. Inserting the space made
      # sirena honour something mermaid ignores.
      expect(node_for("graph TD\nD@{shape:rounded}\n").shape).to eq("rect")
    end

    it "still reads a key written with its space" do
      expect(node_for("graph TD\nD@{ shape: rounded }\n").shape)
        .to eq("rounded")
    end
  end

  describe "shape, then inline class, then metadata" do
    it "accepts them in mermaid's order" do
      node = node_for("graph TD\nA[old]:::hot@{ shape: hex }\n")

      # The bracket label survives a metadata block that does not mention
      # it — mmdc draws this hexagon with "old" inside.
      expect([node.shape, node.classes, node.label])
        .to eq(["hexagon", ":::hot", "old"])
    end

    it "refuses the inline class before the shape" do
      expect { node_for("graph TD\nA:::hot[old]@{ shape: hex }\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "an empty value" do
    # mermaid keeps what the node had rather than clearing it.
    it "leaves the label alone" do
      expect(node_for(%(graph TD\nA[keep]@{ label: }\n)).label).to eq("keep")
    end

    it "leaves the label alone for an empty string too" do
      expect(node_for(%(graph TD\nA[keep]@{ label: "" }\n)).label).to eq("keep")
    end

    it "leaves the shape alone" do
      expect(node_for("graph TD\nA(keep)@{ shape: }\n").shape).to eq("rounded")
    end
  end

  describe "the generated shape table" do
    # Nothing regenerates it in CI, so a name silently disappearing would
    # go unnoticed. mmdc accepts 141 names on this oracle.
    # A size check alone passes when an accepted name is swapped for a
    # bogus one, so the whole key set is asserted against the candidate
    # file minus the six names mermaid rejects.
    def rejected_names
      %w[
        disk-storage multi-doc multi-process multi-rect sub-proc
        subroutine-shape
      ]
    end

    it "carries exactly the names mermaid accepts" do
      probed = File.read("scripts/probes/shape_names.txt")
      candidates = probed.split(/\s+/).reject(&:empty?).uniq

      expect(Sirena::Parser::MERMAID_SHAPES.keys.sort)
        .to eq((candidates - rejected_names).sort)
    end
  end

  describe "a body mermaid accepts and means nothing by" do
    # "It did not raise" passes even when the block quietly renames the
    # node or flattens its shape, so each one asserts the node came
    # through untouched.
    { "empty" => "A(keep)@{}",
      "whitespace only" => "A(keep)@{ }",
      "a key with no value" => "A(keep)@{ label: }",
      "a null value" => "A(keep)@{ shape: null }",
      "a false value" => "A(keep)@{ shape: false }",
      "a zero value" => "A(keep)@{ label: 0 }" }.each do |label, statement|
      it "leaves the node alone for #{label}" do
        node = node_for("graph TD\n#{statement}\n")

        expect([node.shape, node.label]).to eq(%w[rounded keep])
      end
    end

    it "takes a trailing comma, and the shape in front of it" do
      # A trailing comma is legal and means nothing on its own, but the
      # entry before it still counts: mmdc draws this one square.
      node = node_for("graph TD\nA(keep)@{ shape: rect, }\n")

      expect([node.shape, node.label]).to eq(%w[rect keep])
    end
  end

  # mermaid hands the body to js-yaml under its JSON schema and then tests
  # each value for truth. Reading scalars straight off the Psych AST agreed
  # with that only for a plain `key: value`.
  describe "the values js-yaml produces" do
    it "resolves an alias" do
      source = "graph TD\nA@{\n  shape: &s rounded\n  label: *s\n}\n"
      node = node_for(source)

      expect([node.shape, node.label]).to eq(%w[rounded rounded])
    end

    # `Psych::Nodes::Node#to_ruby` is `unsafe_load` wearing a different
    # name. It built a Gem::Requirement out of a node label before the
    # type check downstream refused the value, so a diagram could
    # construct arbitrary Ruby objects. mmdc rejects both of these.
    describe "a ruby-tagged value" do
      {
        "an object tag" => "graph TD\nA@{\n  shape: rounded\n  " \
                           "label: !ruby/object:Gem::Requirement\n    " \
                           "requirements:\n    - x\n}\n",
        "a symbol tag" => "graph TD\nA@{ label: !ruby/symbol boom }\n"
      }.each do |label, source|
        it "refuses #{label}" do
          expect { node_for(source) }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end

      it "builds no object on the way to refusing it" do
        source = "graph TD\nA@{\n  shape: rounded\n  " \
                 "label: !ruby/object:Gem::Requirement\n    " \
                 "requirements:\n    - x\n}\n"
        before = ObjectSpace.each_object(Gem::Requirement).count

        expect { node_for(source) }.to raise_error(Sirena::Parser::ParseError)
        expect(ObjectSpace.each_object(Gem::Requirement).count).to eq(before)
      end
    end

    it "resolves a tag" do
      expect(node_for("graph TD\nA@{ shape: !!str rounded }\n").shape)
        .to eq("rounded")
    end

    it "refuses an anchor that holds an alias" do
      # Flat anchors are fine. Nesting them is how a few lines of YAML
      # become gigabytes, and mermaid has no use for it.
      source = "graph TD\nA@{\n  shape: &a [x]\n  label: &b [*a, *a]\n}\n"

      expect { node_for(source) }
        .to raise_error(Sirena::Parser::ParseError, /anchor/)
    end

    it "takes the first element of a sequence label" do
      # mmdc draws `[one, two]` as `one`, not as `one,two`.
      expect(node_for("graph TD\nA@{ label: [one, two] }\n").label)
        .to eq("one")
    end

    {
      "a sequence shape" => "A@{ shape: [rounded, rect] }",
      "a nested sequence label" => "A@{ label: [[x, y], z] }",
      "an empty sequence label" => "A@{ label: [] }"
    }.each do |label, statement|
      it "refuses #{label}, as mermaid does" do
        expect { node_for("graph TD\n#{statement}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "keeps a string zero, which is truthy" do
      expect(node_for(%(graph TD\nA@{ label: "0" }\n)).label).to eq("0")
    end
  end

  # Mermaid lexes the block before YAML sees it, and its string state opens
  # on a double quote only.
  describe "quoting inside the block" do
    it "turns a newline inside a quoted value into a line break" do
      # mmdc renders `one<br/>two`. Letting YAML fold the newline gave
      # `one two`, which is a different label.
      source = %(graph TD\nA@{ label: "one\ntwo" }\n)

      expect(node_for(source).label).to eq("one<br/>two")
    end

    it "refuses a brace inside a single-quoted value" do
      # The block ends at that brace in mermaid, and mmdc rejects the
      # line. Treating single quotes as a string state accepted it.
      expect { node_for(%(graph TD\nA@{ label: 'a}b' }\n)) }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "still takes a single-quoted value with no brace in it" do
      expect(node_for("graph TD\nA@{ label: 'plain' }\n").label)
        .to eq("plain")
    end
  end

  # A node named twice changes only what the second mention says.
  describe "a node mentioned again" do
    it "resets the shape and keeps the label" do
      node = node_for("graph TD\nA(keep)\nA@{ shape: rect }\n")

      expect([node.shape, node.label]).to eq(%w[rect keep])
    end

    it "keeps both when the block says nothing" do
      node = node_for("graph TD\nA[keep]@{ shape: hexagon }\nA@{}\n")

      expect([node.shape, node.label]).to eq(%w[hexagon keep])
    end

    it "takes a label the second mention does give" do
      node = node_for(%(graph TD\nA(keep)\nA@{ label: "new" }\n))

      expect([node.shape, node.label]).to eq(%w[rounded new])
    end
  end

  describe "forms mermaid refuses" do
    { "whitespace before the brace" => "D @{ shape: rounded }",
      "an unterminated quoted value" => 'A@{ label: "oops }',
      "a duplicate key" => "A@{ shape: rect, shape: circle }" }
      .each do |label, statement|
        it "rejects #{label}" do
          expect { node_for("graph TD\n#{statement}\n") }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end
  end

  describe "nodes without metadata" do
    it "still reads a bracket shape" do
      expect(node_for("graph TD\nA(x)\n").shape).to eq("rounded")
    end

    it "still reads an inline class" do
      expect(node_for("graph TD\nA:::c\n").classes).to eq(":::c")
    end

    it "still defaults a bare node to a rectangle" do
      node = node_for("graph TD\nA\n")

      expect(node.shape).to eq("rect")
      expect(node.label).to eq("A")
    end
  end
end
