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
    let(:corpus_dir) { File.join(__dir__, "../../mermaid/flowchart") }

    it "gives every member of a three-node group its own label" do
      source = File.read(File.join(corpus_dir,
                                   "059_parser_should_be_possible_to_use_" \
                                   "syntax_to_add_labels_on_multi_nodes_54.mmd"))
      nodes = parse_flowchart(source, header: "").nodes

      expect(nodes.map { |n| [n.id, n.label] })
        .to eq([["n2", '"label for n2"'], ["n4", "label for n4"],
                ["n5", "label for n5"]])
    end

    it "links one source to every member of a three-node target group" do
      source = File.read(File.join(corpus_dir,
                                   "060_parser_should_be_possible_to_use_" \
                                   "syntax_to_add_labels_on_multi_nodes_" \
                                   "with_edge_link_55.mmd"))
      diagram = parse_flowchart(source, header: "")

      expect(diagram.edges.map { |e| "#{e.source_id}>#{e.target_id}" })
        .to eq(%w[A>B A>C A>E])
      expect(diagram.nodes.map(&:id)).to eq(%w[A B C E D])
    end

    # These render on this branch and raise ParseError on every one of the
    # 14 against origin/main, so the bare matcher is a real signal here.
    # Keep it: it is the only check that the whole bucket clears, and the
    # two examples above carry the assertions for the shapes it covers.
    it "finds the corpus bucket it claims to cover" do
      expect(amp_bucket_paths(corpus_dir).size).to eq(14)
    end

    FlowchartParserHelpers
      .amp_bucket_paths(File.join(__dir__, "../../mermaid/flowchart"))
      .each do |path|
      it "renders #{File.basename(path, '.mmd')}" do
        expect { Sirena::Engine.new.render(File.read(path)) }
          .not_to raise_error
      end
    end
  end
end
