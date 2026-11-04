# frozen_string_literal: true

require "spec_helper"
require_relative "activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity::Parser do
  include ActivityHelpers

  it "chains start, actions and stop", :aggregate_failures do
    diagram = parse("start\n:one;\n:two;\nstop")

    expect(kinds(diagram)).to eq(%i[start action action stop])
    expect(diagram.edges.map { |e| [e.from.text, e.to.text] })
      .to eq([[nil, "one"], %w[one two], ["two", nil]])
  end

  it "reads a multi-line action and drops creole markup" do
    diagram = parse(":process\n  __sequence__ and **bold**;")

    expect(diagram.nodes.first.lines).to eq(["process", "sequence and bold"])
  end

  it "reads a literal backslash-n as a line break" do
    expect(parse(':a\nb;').nodes.first.lines).to eq(%w[a b])
  end

  it "reads the colour of `#colour:action;`" do
    diagram = parse("#pink:red;\n#33668E:hex;")

    expect(diagram.nodes.map(&:fill)).to eq(["pink", "#33668E"])
  end

  it "labels the next edge from an arrow with text" do
    diagram = parse(":a;\n-> goes on\nand on;\n:b;")

    expect(edge(diagram, "a", "b").label).to eq("goes on\nand on")
  end

  it "reads arrow colour and style" do
    diagram = parse(":a;\n-[#green,dashed]->\n:b;")

    expect(edge(diagram, "a", "b"))
      .to have_attributes(colour: "green", style: :dashed, label: nil)
  end

  it "refuses an unknown arrow style" do
    expect do
      parse(":a;\n-[#red,wavy]->\n:b;")
    end.to raise_unsupported("arrow style")
  end

  it "reads a title" do
    expect(parse("title My flow\n:a;").title).to eq("My flow")
  end

  describe "if" do
    let(:diagram) do
      parse(<<~PUML)
        start
        if (ok?) then (yes)
        :a;
        elseif (maybe?) then (perhaps)
        :b;
        else (no)
        :c;
        endif
        :d;
      PUML
    end

    it "makes a decision per if and elseif and labels the branches",
       :aggregate_failures do
      expect(edge(diagram, "ok?", "a").label).to eq("yes")
      expect(edge(diagram, "maybe?", "b").label).to eq("perhaps")
      expect(edge(diagram, "maybe?", "c").label).to eq("no")
    end

    it "joins the three branches in one merge before the next action",
       :aggregate_failures do
      merge = diagram.nodes.find { |n| n.kind == :merge }

      expect(diagram.edges.select { |e| e.to.equal?(merge) }.size).to eq(3)
      expect(edge(diagram, nil, "d").from).to equal(merge)
    end

    it "reads `is (value) then` as the label of the then branch" do
      diagram = parse("if (color?) is (red) then\n:x;\nendif")

      expect(edge(diagram, "color?", "x").label).to eq("red")
    end

    it "sends the decision straight to the merge when there is no else" do
      diagram = parse("if (x?) then\n:a;\nendif\n:b;")
      merge = diagram.nodes.find { |n| n.kind == :merge }

      expect(diagram.edges.map { |e| [e.from.text, e.to] })
        .to include(["x?", merge])
    end

    it "does not merge when every branch stops" do
      diagram = parse("if (x?) then\nstop\nelse\nstop\nendif")

      expect(kinds(diagram)).not_to include(:merge)
    end
  end

  describe "while" do
    let(:diagram) do
      parse("while (more?) is (yes)\n:work;\nendwhile (done)\n:after;")
    end

    it "loops the body back to the decision and exits with the label",
       :aggregate_failures do
      expect(edge(diagram, "work", "more?")).not_to be_nil
      expect(edge(diagram, "more?", "after").label).to eq("done")
      expect(edge(diagram, "more?", "work").label).to eq("yes")
    end
  end

  describe "repeat" do
    let(:diagram) do
      parse(<<~PUML)
        repeat
        :work;
        repeat while (again?) is (yes) not (no)
        :after;
      PUML
    end

    it "loops the decision back to the start of the body" do
      back = diagram.edges.find { |e| e.to.kind == :merge && e.from.text }

      expect(back.label).to eq("yes")
    end

    it "leaves by the not label" do
      expect(edge(diagram, "again?", "after").label).to eq("no")
    end
  end

  describe "fork" do
    it "branches from one bar and joins on another", :aggregate_failures do
      diagram = parse("fork\n:a;\nfork again\n:b;\nend fork\n:c;")
      bars = diagram.nodes.select { |n| n.kind == :bar }

      expect(bars.size).to eq(2)
      expect(diagram.edges.count { |e| e.from.equal?(bars.first) }).to eq(2)
      expect(diagram.edges.count { |e| e.to.equal?(bars.last) }).to eq(2)
    end

    it "joins an `end merge` on a merge node" do
      diagram = parse("fork\n:a;\nfork again\n:b;\nend merge")

      expect(kinds(diagram)).to include(:merge)
    end
  end

  describe "switch" do
    let(:diagram) do
      parse(<<~PUML)
        switch (t?)
        case (A)
        :one;
        case (B)
        :two;
        endswitch
        :end;
      PUML
    end

    it "branches one labelled edge per case", :aggregate_failures do
      expect(edge(diagram, "t?", "one").label).to eq("A")
      expect(edge(diagram, "t?", "two").label).to eq("B")
    end

    it "joins the cases before the next action" do
      expect(edge(diagram, nil, "end").from.kind).to eq(:merge)
    end
  end

  describe "partitions, lanes and notes" do
    it "tags nodes with the partition they are in" do
      diagram = parse("partition Work {\n:a;\n}\n:b;")

      expect(diagram.nodes.map(&:partition)).to eq(["Work", nil])
    end

    it "refuses a nested partition" do
      source = "partition A {\npartition B {\n:x;\n}\n}"

      expect { parse(source) }.to raise_unsupported("nested partition")
    end

    it "tags nodes with the swimlane and keeps lanes in order",
       :aggregate_failures do
      diagram = parse("|#pink|First|\n:a;\n|Second|\n:b;\n|First|\n:c;")

      expect(diagram.nodes.map(&:lane)).to eq(%w[First Second First])
      expect(diagram.lanes).to eq([["First", "pink"], ["Second", nil]])
    end

    it "attaches a one-line note to the activity before it" do
      diagram = parse(":a;\nnote right: look here\n:b;")

      expect(node(diagram, "a").notes.map { |n| [n.side, n.text] })
        .to eq([[:right, "look here"]])
    end

    it "attaches a block note" do
      diagram = parse(":a;\nnote left\none\ntwo\nend note")

      expect(node(diagram, "a").notes.first.lines).to eq(%w[one two])
    end
  end

  describe "refusals" do
    {
      "an image" => [":see <img:a.png>;", "image"],
      "an unknown statement" => ["start\nsplit", "statement"],
      "an unterminated action" => [":never ends", "unterminated"],
      "an unclosed if" => ["if (x?) then\n:a;", "unclosed if"],
      "an endif without if" => [":a;\nendif", "endif"],
      "a note with nothing before it" => ["note right: x", "note"],
    }.each do |name, (source, construct)|
      it "refuses #{name}" do
        expect { parse(source) }.to raise_unsupported(construct)
      end
    end

    it "names the line of the refusal" do
      expect { parse("start\nsplit") }.to raise_unsupported("line 3")
    end
  end
end
