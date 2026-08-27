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
    it "refuses whitespace before the inline class" do
      # mmdc rejects `A[x] :::hot`, and allowing it captured the class
      # with its leading space still attached.
      expect { node_for("graph TD\nA[x] :::hot@{ shape: rounded }\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "keeps an empty bracket label empty" do
      # `A[ ]` is a node with nothing in it. Treating it as absent named
      # the node after itself.
      node = node_for("graph TD\nA[ ]@{ shape: rounded }\n")

      expect([node.shape, node.label]).to eq(["rounded", ""])
    end

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

    # `Psych.safe_load` was not safe enough: it still calls any handler
    # registered with `Psych.add_domain_type`, which is a host-global list,
    # and the handler's return value became the node label. Values are
    # resolved off the AST now, so nothing reaches a materialiser.
    describe "a tagged value" do
      around do |example|
        example.run
      ensure
        Psych.domain_types.delete("tag:yaml.org,2002:omap")
      end

      it "never calls a registered domain handler" do
        called = 0
        Psych.add_domain_type("yaml.org,2002", "omap") do |_t, v|
          called += 1
          v
        end

        expect { node_for("graph TD\nA@{ label: !!omap foo }\n") }
          .to raise_error(Sirena::Parser::ParseError, /Unsupported tag/)
        expect(called).to eq(0)
      end

      it "refuses a ruby object tag" do
        source = "graph TD\nA@{\n  shape: rounded\n  " \
                 "label: !ruby/object:Gem::Requirement\n    " \
                 "requirements:\n    - x\n}\n"

        expect { node_for(source) }
          .to raise_error(Sirena::Parser::ParseError, /Unsupported tag/)
      end
    end

    # js-yaml's JSON schema, which is what mermaid parses with. Psych's
    # implicit resolution is wider and disagreed on all of these.
    describe "the value schema" do
      {
        "a date" => ["graph TD\nA@{ label: 2024-01-01 }\n", "2024-01-01"],
        "a quoted zero" => ["graph TD\nA@{ label: \"0\" }\n", "0"]
      }.each do |label, (source, expected)|
        it "reads #{label} as a string" do
          expect(node_for(source).label).to eq(expected)
        end
      end

      it "does not resolve no to false" do
        # Psych makes this `false`, which silently skipped the key. mmdc
        # looks for a shape called "no" and refuses the source.
        expect { node_for("graph TD\nA(keep)@{ shape: no }\n") }
          .to raise_error(Sirena::Parser::ParseError, /No such shape/)
      end

      it "refuses a bare number as a label" do
        expect { node_for("graph TD\nA@{ label: 1 }\n") }
          .to raise_error(Sirena::Parser::ParseError, /Unusable label/)
      end

      it "treats NaN as falsy, as JavaScript does" do
        expect(node_for("graph TD\nA(keep)@{ label: .nan }\n").label)
          .to eq("keep")
      end

      it "refuses Infinity, which is a number like any other" do
        expect { node_for("graph TD\nA(keep)@{ label: .inf }\n") }
          .to raise_error(Sirena::Parser::ParseError, /Unusable label/)
      end
    end

    # js-yaml's JSON_SCHEMA reads YAML 1.1, not JSON: a word has three
    # spellings, a number takes a sign and `_` groups, and 0b/0o/0x
    # count. Reading it as JSON made `label: NULL` the string "NULL"
    # where mmdc keeps the old label, and let `label: +1` through where
    # mmdc errors. Every value below is a measured mmdc verdict.
    describe "the js-yaml scalar table" do
      # Falsy in JavaScript, so mermaid skips the key and the node keeps
      # what it had.
      %w[
        Null NULL ~ False FALSE 0 00 +0 -0 000 0_0 0x0 0b0 0.0 0. .0 0e5
        .nan .NaN .NAN
      ].each do |value|
        it "skips a label of #{value}" do
          expect(node_for("graph TD\nA(keep)@{ label: #{value} }\n").label)
            .to eq("keep")
        end
      end

      # Truthy and not a string, which is the one thing mermaid cannot
      # use. Every `_` is dropped before the number is read, so `1__0`
      # is ten and `0_1.5` is one and a half.
      %w[
        True TRUE +1 -1 08 010 0x1F 0o17 0b101 -0x1F 1_000 1__0 0x_1 0_1
        0_1.5 .5 1. +1.5 1e+3 .inf .Inf .INF +.inf -.Inf
      ].each do |value|
        it "refuses a label of #{value}" do
          expect { node_for("graph TD\nA(keep)@{ label: #{value} }\n") }
            .to raise_error(Sirena::Parser::ParseError, /Unusable label/)
        end
      end

      # Near misses that stay strings: the wrong case, an uppercase base
      # prefix, a digit out of range, a stray `_`, and a sign on the two
      # float branches that have none.
      %w[
        nUll tRue Nul 1_ _1 0X1 0b12 0o8 0x 0x_ +_1 1e_3 1e .e3 -.5 +.5
        -.0 -.nan .iNf .nAn ~~
      ].each do |value|
        it "keeps #{value} as a string label" do
          expect(node_for("graph TD\nA(keep)@{ label: #{value} }\n").label)
            .to eq(value)
        end
      end

      it "skips a falsy shape and leaves the node alone" do
        node = node_for("graph TD\nA(keep)@{ shape: NULL }\n")

        expect([node.shape, node.label]).to eq(%w[rounded keep])
      end

      it "refuses a shape that resolved to a number" do
        expect { node_for("graph TD\nA(keep)@{ shape: 0b1 }\n") }
          .to raise_error(Sirena::Parser::ParseError, /Unusable shape/)
      end
    end

    # Mermaid reads `shape` and `label` and ignores the rest, a merge key
    # included. Validating every entry refused diagrams mmdc draws.
    describe "a key mermaid does not read" do
      it "is ignored" do
        node = node_for("graph TD\nA(keep)@{ extra: true }\n")

        expect([node.shape, node.label]).to eq(%w[rounded keep])
      end

      it "does not stop the keys it does read" do
        expect(node_for("graph TD\nA@{ extra: true, shape: rounded }\n").shape)
          .to eq("rounded")
      end

      it "ignores a merge key" do
        expect(node_for("graph TD\nA@{\n  <<: x\n  label: y\n}\n").label)
          .to eq("y")
      end
    end

    # An alias that reaches an anchor already being expanded is a cycle.
    # The structural guard catches the shallow forms; this catches the
    # rest, including an anchor nested under a sequence.
    it "refuses a circular anchor nested in a sequence" do
      source = "graph TD\nA@{\n  label: [&a [y, *a], z]\n  shape: rounded\n}\n"

      expect { node_for(source) }
        .to raise_error(Sirena::Parser::ParseError, /Circular anchor/)
    end

    it "takes an explicit string tag over the implicit rules" do
      # mmdc draws this as "1". Without the tag it is a number and refused.
      expect(node_for("graph TD\nA@{ label: !!str 1 }\n").label).to eq("1")
      expect { node_for("graph TD\nA@{ label: 1 }\n") }
        .to raise_error(Sirena::Parser::ParseError)
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

    it "refuses an unmatched double quote" do
      # mermaid's lexer stays in its string state to the end of the block
      # and refuses the source. Falling through to the generic body branch
      # took `a"b` as a label.
      expect { node_for(%(graph TD\nA@{ label: a"b }\n)) }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "collapses the indentation after a quoted newline" do
      # mmdc renders `one<br/>two`, not `one<br/><br/>  two`.
      source = %(graph TD\nA@{ label: "one\n\n  two" }\n)

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
