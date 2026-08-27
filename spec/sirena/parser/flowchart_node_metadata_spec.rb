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

    # Whitespace is free-form in mermaid, and the corpus uses every one of
    # these spellings.
    {
      "no spaces" => "D@{shape:rounded}",
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
      expect(node_for("graph TD\nD@{ shape: 'rect' }\n").shape).to eq("rect")
    end

    it "keeps whitespace inside a quoted value" do
      # An unquoted value runs to the brace and picks up the space before
      # it; a quoted one means exactly what it says.
      expect(node_for(%(graph TD\nD@{ label: " padded " }\n)).label)
        .to eq(" padded ")
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
      "in-out" => "hexagon", "lean-r" => "parallelogram"
    }.each do |name, expected|
      it "maps #{name} to #{expected}" do
        expect(node_for("graph TD\nD@{ shape: #{name} }\n").shape)
          .to eq(expected)
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
