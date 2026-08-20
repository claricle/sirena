# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  def node_ids(source)
    described_class.new.parse(source).nodes.map(&:id).sort
  end

  describe "accessibility statements" do
    # mermaid puts these in the SVG's aria attributes. They are ordinary
    # statements in a diagram and had no rule at all.
    it "takes accTitle" do
      source = "graph TD\naccTitle: Big decisions\nA-->B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "takes accDescr" do
      source = "graph TD\naccDescr: Some text\nA-->B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "takes the braced accDescr block" do
      source = "graph TD\naccDescr {\n  multi line\n}\nA-->B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "does not turn the block into a node" do
      # This is the reason the bucket matters. Without a rule, the braced
      # form parsed as a node called accDescr whose label was the block —
      # a silent misparse that rendered a phantom node rather than failing.
      source = "graph TD\naccDescr {\n  multi line\n}\nA-->B\n"

      expect(node_ids(source)).not_to include("accDescr")
    end

    it "leaves an ordinary node starting with acc alone" do
      expect(node_ids("graph TD\naccount-->B\n")).to eq(%w[B account])
    end
  end

  describe "a diagram with no accessibility statement" do
    it "is unchanged" do
      expect(node_ids("graph TD\nA-->B\n")).to eq(%w[A B])
    end
  end
end
