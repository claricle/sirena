# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart do
  include FlowchartParserHelpers

  describe "nodes joined with &" do
    it "declares every node of a group that has no link" do
      expect(parse_flowchart("A & B & C").nodes.map(&:id)).to eq(%w[A B C])
    end

    it "links every source to every target" do
      expect(edge_links("A & B --> C & D"))
        .to eq(%w[A>C A>D B>C B>D])
    end

    it "carries a group through a chain of links" do
      expect(edge_links("A & B --> C --> D & E"))
        .to eq(%w[A>C B>C C>D C>E])
    end

    it "gives each edge of the product the same label" do
      labels = parse_flowchart("A & B -->|t| C").edges.map(&:label)

      expect(labels).to eq(%w[|t| |t|])
    end

    it "keeps each node's own shape data" do
      nodes = parse_flowchart("D@{ shape: rounded } & E@{ label: two }").nodes

      expect(nodes.map { |n| [n.id, n.shape, n.label] })
        .to eq([["D", "rounded", "D"], %w[E rect two]])
    end

    it "takes a group after an inline-labelled link" do
      expect(edge_links("A -- t --> B & C")).to eq(%w[A>B A>C])
    end

    ["A &", "A & & B", "A & --> B", "A &\nB", "A\n& B", "A[x]&B[y]",
     "A[x] &B[y]", "A[x]& B[y]", "A --> B[x]&C[y]"].each do |source|
      it "refuses #{source.inspect}" do
        expect { parse_flowchart(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "the flowchart corpus cases behind the & bucket" do
    Dir[File.join(__dir__, "../../mermaid/flowchart/*.mmd")].select do |f|
      File.basename(f).match?(
        /\A\d+_parser_should_(handle_basic_shape_data_statements_with_|
                              be_possible_to_use_syntax_to_add_labels_on_multi)/x
      )
    end.each do |path|
      it "renders #{File.basename(path, '.mmd')}" do
        expect { Sirena::Engine.new.render(File.read(path)) }
          .not_to raise_error
      end
    end
  end
end
