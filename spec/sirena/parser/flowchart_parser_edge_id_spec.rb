# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  include FlowchartParserHelpers

  describe "an edge id written before the link" do
    it "leaves the id out of the nodes and keeps the edge" do
      diagram = parse_flowchart("A e1@--> B")

      expect(diagram.nodes.map(&:id)).to eq(%w[A B])
      expect(diagram.edges.map { |e| [e.source_id, e.target_id] })
        .to eq([%w[A B]])
    end

    it "takes the id on a link with an inline label" do
      expect(parse_flowchart("A e1@-- text --> B").edges.map(&:label)).to eq(["text"])
    end

    it "takes the id on a grouped link" do
      expect(parse_flowchart("A & B e1@--> C & D").edges.size).to eq(4)
    end

    it "does not read a metadata block as an edge id" do
      expect(parse_flowchart("A@{ shape: rect } --> B").edges.size).to eq(1)
    end
  end

  describe "a properties block addressed to an edge id" do
    it "sets no node when the edge was declared before it" do
      source = "A e1@--> B\ne1@{ animate: true }"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "sets no node for a later block that repeats the id" do
      source = "A e1@--> B\ne1@{ animate: true }\ne1@{ animate: false }"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "is still a node when no edge carries that id" do
      source = "A e1@--> B\ne2@{ animate: true }"

      expect(node_ids(source)).to eq(%w[A B e2])
    end

    it "is still a node when a plain mention repeats the id" do
      source = "A e1@--> B\ne1 --> C"

      expect(node_ids(source)).to eq(%w[A B e1 C])
    end

    it "is still a node when it comes before the edge" do
      source = "e1@{ animate: true }\nA e1@--> B"

      expect(node_ids(source)).to eq(%w[e1 A B])
    end
  end

  describe "an @ that is not an edge id" do
    it "keeps an @ inside a link label" do
      expect(edge_tuples("A --me@host--> B").first[0..2]).to eq(["A", "B", "me@host"])
    end

    it "keeps an @ inside a quoted link label" do
      expect(edge_links('A --"me@host"--> B')).to eq(["A>B"])
    end

    it "keeps an @ inside a piped label" do
      expect(edge_links('A -->|"me@host"| B')).to eq(["A>B"])
    end

    it "keeps an @ that closes a link label" do
      expect(edge_tuples("A --me@--> B").first[0..2]).to eq(["A", "B", "me@"])
    end

    it "refuses an id glued to the separator before it" do
      expect { parse_flowchart("A;e1@--> B") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "an edge id with unusual spacing or characters" do
    it "takes whitespace between the @ and the link" do
      expect(edge_links("A e1@ ==> B")).to eq(%w[A>B])
    end

    it "takes a ; inside the id" do
      expect(edge_links("A a;b@--> B")).to eq(%w[A>B])
    end

    it "takes a hyphenated id" do
      expect(edge_links("A x-id@--> B")).to eq(%w[A>B])
    end

    it "takes an id glued to the & before it" do
      expect(edge_links("A &x@--> B")).to eq(%w[A>B])
    end

    it "refuses an id that opens with a quote" do
      expect { parse_flowchart('A "x@--> B') }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "takes properties for an id outside the node charset" do
      source = "A e:x@--> B\ne:x@{ animate: true }"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "still checks the YAML of properties for such an id" do
      expect { parse_flowchart("A e:x@--> B\ne:x@{ animate: [ }") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "draws a node for such an id no link declared" do
      expect(node_ids("A --> B\ne:x@{ animate: true }")).to eq(%w[A B e:x])
    end

    it "takes a no-break space between the @ and the link" do
      expect(edge_links("A e1@\u00A0--> B")).to eq(%w[A>B])
    end

    it "takes a comment line between the @ and the link" do
      expect(edge_links("A e1@\n%% note\n--> B")).to eq(%w[A>B])
    end

    it "takes an id opening with a brace" do
      expect(edge_links("A {x@--> B")).to eq(%w[A>B])
    end

    it "still rejects malformed properties addressed to an edge" do
      expect { parse_flowchart("A e1@--> B\ne1@{ animate: [ }") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "a properties block that is an endpoint of a link" do
    it "keeps the edge that ends at it" do
      expect(edge_links("A e1@--> B\nC --> e1@{ shape: rect }"))
        .to eq(%w[A>B C>e1])
    end

    it "keeps the edge that starts at a grouped one" do
      expect(edge_links("A e1@--> B\nC & e1@{ shape: rect } --> D"))
        .to eq(%w[A>B C>D e1>D])
    end
  end

  describe "the flowchart corpus cases behind the edge-id bucket" do
    Dir[File.join(__dir__, "../../mermaid/flowchart/*.mmd")].select do |f|
      File.basename(f).match?(
        /\A\d+_parser_should_handle_(unique_edge_creation_with_using|
            redefine_same_edge_ids_again|overriding_edge_animate_again|
            normal_edges_where_you_also_have_a_node_with_metadata_26)/x
      )
    end.each do |path|
      it "renders #{File.basename(path, '.mmd')}" do
        expect { Sirena::Engine.new.render(File.read(path)) }
          .not_to raise_error
      end
    end
  end
end
