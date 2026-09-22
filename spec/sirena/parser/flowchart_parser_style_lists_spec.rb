# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart do
  let(:node_ids) do
    ->(source) { described_class.new.parse(source).nodes.map(&:id).sort }
  end

  describe "a comma inside a style or classDef value" do
    [
      "style A fill:#F99,stroke:red",
      "style A background:#fff,border:1px solid red",
      "classDef x fill:#f9f,stroke:#333,stroke-width:4px",
    ].each do |declaration|
      it "takes #{declaration.inspect}" do
        expect(node_ids.call("graph TD\nA-->B\n#{declaration}\n")).to eq(%w[A B])
      end
    end
  end

  describe "an empty item in a comma list" do
    [
      "style A fill:red,",
      "style A fill:red,,stroke:blue",
      "style A ,fill:red",
      "style A fill:#f9f,",
      "classDef x fill:red,"
    ].each do |declaration|
      it "refuses #{declaration.inspect}" do
        expect { node_ids.call("graph TD\nA\n#{declaration}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "a space in place of a comma item" do
    [
      "style A fill:red, ",
      "style A fill:red, ,stroke:blue",
      "style A fill:red, ;B",
      "classDef x fill:red, "
    ].each do |declaration|
      it "takes #{declaration.inspect}, as mermaid does" do
        expect(node_ids.call("graph TD\nA\n#{declaration}\n")).to include("A")
      end
    end
  end

  describe "a comma directly before a semicolon" do
    ["style A fill:#f9f,;B", "classDef x fill:#f9f,;B"].each do |declaration|
      it "takes #{declaration.inspect}, where the `;` is value text" do
        expect(node_ids.call("graph TD\nA\n#{declaration}\n")).to include("A")
      end
    end

    it "refuses `style A fill:red,;B`, where the `;` ends the item" do
      expect { node_ids.call("graph TD\nA\nstyle A fill:red,;B\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "a hash after a space" do
    [
      "style A fill:red,stroke: #fff,color:blue;B",
      "classDef x fill:red,stroke: #fff,color:blue;B",
      "style A #x a:b;B"
    ].each do |declaration|
      it "does not swallow the node after #{declaration.inspect}" do
        source = "graph TD\nA\n#{declaration}\n"
        expect(node_ids.call(source)).to eq(%w[A B])
      end
    end

    it "still swallows the `;` after `fill:#f9f`" do
      expect(node_ids.call("graph TD\nA\nstyle A fill:#f9f;B\n")).to eq(%w[A])
    end
  end

  describe "a multi-class classDef" do
    it "takes `classDef a,b props` and keeps the diagram's nodes" do
      source = "graph TD\nA\nclassDef first,second fill:#bbb,stroke:red\n"
      expect(node_ids.call(source)).to eq(%w[A])
    end
  end

  describe "a style statement for a node nothing else mentions" do
    it "draws that node, as corpus case 141 and 142 do" do
      source = "graph TD;style R background:#fff,border:1px solid red;"
      expect(node_ids.call(source)).to eq(%w[R])
    end

    it "draws an undeclared node and leaves a declared one as it was" do
      source = "graph TD\nR{Choose}\nstyle R fill:red\nstyle Q fill:red\n"
      diagram = described_class.new.parse(source)
      expect(diagram.nodes.map { |n| [n.id, n.label, n.shape] }.sort)
        .to eq([%w[Q Q rect], %w[R Choose rhombus]])
    end
  end

  describe "the flowchart corpus cases behind the comma bucket" do
    Dir[File.join(__dir__, "../../mermaid/flowchart/*.mmd")].select do |f|
      File.basename(f).match?(/\A(01[1-9]|020|141|142|145)_/)
    end.each do |path|
      it "renders #{File.basename(path, '.mmd')}" do
        source = File.read(path)
        expect { Sirena::Engine.new.render(source) }.not_to raise_error
      end
    end
  end
end
