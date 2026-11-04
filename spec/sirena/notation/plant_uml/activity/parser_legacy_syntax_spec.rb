# frozen_string_literal: true

require "spec_helper"
require_relative "activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity::Parser do
  include ActivityHelpers

  it "reads (*) as start and end around quoted activities",
     :aggregate_failures do
    diagram = parse(%((*) --> "One"\n--> "Two"\n-->(*)))

    expect(kinds(diagram)).to eq(%i[start action action stop])
    expect(diagram.edges.size).to eq(3)
  end

  it "reads an arrow label after the arrow" do
    diagram = parse('(*) -->[go] "One"')

    expect(diagram.edges.first.label).to eq("go")
  end

  it "ignores a direction hint" do
    diagram = parse(%((*) -left-> "One"\n-up-> "Two"))

    expect(diagram.edges.map { |e| [e.from.text, e.to.text] })
      .to eq([[nil, "One"], %w[One Two]])
  end

  it "reads a quoted activity that spans lines" do
    diagram = parse(%((*) --> "first line\nsecond <b>line</b>"))

    expect(diagram.nodes.last.lines).to eq(["first line", "second line"])
  end

  it "refers back to an activity by its alias" do
    diagram = parse(%((*) --> "One" as A1\n--> "Two"\nA1 --> "Three"))

    expect(edge(diagram, "One", "Three")).not_to be_nil
  end

  it "refuses an alias that was never defined" do
    expect do
      parse(%((*) --> "One"\nNOPE --> "Two"))
    end.to raise_unsupported("undefined activity")
  end

  it "shares one bar between every arrow that names it" do
    diagram = parse(%((*) --> ===B===\n--> "One"\n"One" --> ===B===))

    expect(diagram.nodes.count { |n| n.kind == :bar }).to eq(1)
  end

  describe "if" do
    let(:diagram) do
      parse(<<~PUML)
        (*) --> "Start"
        if "ok?" then
        -->[yes] "A"
        --> (*)
        else
        ->[no] "B"
        --> "C"
        endif
        --> "After"
      PUML
    end

    it "labels each branch from the decision", :aggregate_failures do
      expect(edge(diagram, "ok?", "A").label).to eq("yes")
      expect(edge(diagram, "ok?", "B").label).to eq("no")
    end

    it "leaves a branch that ends at (*) out of the merge",
       :aggregate_failures do
      expect(edge(diagram, "C", "After")).not_to be_nil
      expect(kinds(diagram)).not_to include(:merge)
    end

    context "with two live branches" do
      let(:diagram) do
        parse(<<~PUML)
          (*) --> "S"
          if "x" then
          --> "A"
          else
          --> "B"
          endif
          --> "Z"
        PUML
      end

      it "merges them before the next activity" do
        expect(edge(diagram, nil, "Z").from.kind).to eq(:merge)
      end
    end

    it "refuses else without if" do
      expect { parse(%((*) --> "S"\nelse)) }.to raise_unsupported("else/endif")
    end

    it "refuses an unclosed if" do
      expect do
        parse(%((*) --> "S"\nif "x" then\n--> "A"))
      end.to raise_unsupported("unclosed if")
    end
  end

  it "refuses an image inside an activity" do
    expect { parse(%((*) --> "pic <img:a.png>")) }.to raise_unsupported("image")
  end

  it "refuses an unknown statement" do
    expect do
      parse(%((*) --> "S"\nskinparam x y))
    end.to raise_unsupported("statement")
  end
end
