# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart do
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

    it "takes a label no node could use" do
      expect(node_ids("A e1@--> B\ne1@{ label: [] }")).to eq(%w[A B])
    end

    it "takes a block whose YAML is null" do
      expect(node_ids("A e1@--> B\ne1@{\nnull\n}")).to eq(%w[A B])
    end

    it "is still a node when no edge carries that id" do
      source = "A e1@--> B\ne2@{ animate: true }"

      expect(node_ids(source)).to eq(%w[A B e2])
    end

    it "sets no node for a class shorthand addressed to the edge" do
      expect(node_ids("A e1@--> B\ne1:::foo")).to eq(%w[A B])
    end

    it "sets no node for a shaped class reference to the edge" do
      expect(node_ids("A e1@--> B\ne1[x]:::foo")).to eq(%w[A B])
    end

    it "sets no node for an edge reference joined by & to a node" do
      expect(node_ids("A e1@--> B\ne1@{ animate: true } & C"))
        .to eq(%w[A B C])
    end

    it "sets no node for an edge reference later in the & group" do
      expect(node_ids("A e1@--> B\nC & e1:::foo")).to eq(%w[A B C])
    end

    it "keeps a plain edge reference as an endpoint without creating a node" do
      source = "A e1@--> B\ne1 --> C"

      expect([node_ids(source), edge_links(source)])
        .to eq([%w[A B C], %w[A>B e1>C]])
    end

    it "sets no node for a bare, linkless mention with no metadata or class" do
      source = "A e1@--> B\ne1"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "sets no node for a shaped, linkless mention with no metadata or class" do
      source = "A e1@--> B\ne1[shaped]"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "is still a node when it comes before the edge" do
      source = "e1@{ animate: true }\nA e1@--> B"

      expect(node_ids(source)).to eq(%w[e1 A B])
    end

    it "gives the block to the edge when a node shares its id" do
      plain = parse_flowchart("A --> e1\nC e1@--> D").find_node("e1")
      source = "A --> e1\nC e1@--> D\ne1@{ shape: circle }"
      node = parse_flowchart(source).find_node("e1")

      expect([node.shape, node.label]).to eq([plain.shape, plain.label])
    end

    it "gives no shaped mention to a node that shares the id" do
      node = parse_flowchart("A --> e1\nC e1@--> D\ne1((x))").find_node("e1")

      expect(node.label).to eq("e1")
    end

    it "sets no node for a style line addressed to the edge" do
      expect(node_ids("A e1@--> B\nstyle e1 fill:#f00")).to eq(%w[A B])
    end

    it "still styles a node named before the edge" do
      expect(node_ids("style e1 fill:#f00\nA e1@--> B")).to eq(%w[e1 A B])
    end

    it "keeps a node's own class when an unrelated edge shares its id" do
      source = "A --> e1\nC e1@--> D\ne1:::foo"

      diagram = parse_flowchart(source)

      expect(diagram.find_node("e1").classes).to eq(":::foo")
    end

    it "keeps a shared node inside the subgraph that mentions the edge" do
      source = <<~MERMAID
        A --> e1
        C e1@--> D
        subgraph s
          e1:::foo
        end
      MERMAID

      diagram = parse_flowchart(source)

      expect(diagram.subgraphs.first.node_ids).to eq(["e1"])
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

    {
      "A ==me@==> B" => "thick_arrow", "A -.me@.-> B" => "dotted_arrow",
      "A o--me@--o B" => "circle_both", "A <--me@--> B" => "arrow_both",
      "A x--me@--x B" => "cross_both"
    }.each do |source, arrow|
      it "keeps an @ that closes the label of #{source}" do
        expect(edge_tuples(source)).to eq([["A", "B", "me@", arrow]])
      end
    end

    # Deciding that the `@` ends no edge id scans every line after it. A
    # scan that can split those lines more than one way takes minutes here.
    { "blank lines" => "\n" * 30, "comment lines" => "\n%%c\n " * 30 }
      .each do |kind, filler|
      it "refuses an @ followed by #{kind} and no link, promptly" do
        Timeout.timeout(5) do
          expect { parse_flowchart("A x@#{filler}Z") }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end
    end
  end

  describe "an edge id with unusual spacing or characters" do
    it "takes a no-break space before the id" do
      expect(edge_links("A\u00A0e1@--> B")).to eq(%w[A>B])
    end

    it "takes whitespace between the @ and the link" do
      expect(edge_links("A e1@ ==> B")).to eq(%w[A>B])
    end

    it "takes a ; inside the id" do
      expect(edge_links("A a;b@--> B")).to eq(%w[A>B])
    end

    it "takes a hyphenated id" do
      expect(edge_links("A x-id@--> B")).to eq(%w[A>B])
    end

    it "takes an @ inside the id" do
      expect(edge_links("A x@y@--> B")).to eq(%w[A>B])
    end

    it "takes an internal @ before a link-like character" do
      expect(edge_links("A x@-@--> B")).to eq(%w[A>B])
    end

    it "takes an id that starts with a semicolon" do
      expect(edge_links("A ;x@--> B")).to eq(%w[A>B])
    end

    it "takes an id that starts with two dots" do
      expect(edge_links("A ..x@--> B")).to eq(%w[A>B])
    end

    it "refuses an id beginning with an earlier lexer token" do
      aggregate_failures do
        %w[
          style style-x classDef default graph flowchart-elk subgraph end _self
          accTitle:x accDescr:x accDescr{x
        ].each do |id|
          source = "A #{id}@--> B"

          expect { parse_flowchart(source) }
            .to raise_error(Sirena::Parser::ParseError), source.inspect
        end
      end
    end

    it "takes a similar id that no earlier lexer token claims" do
      aggregate_failures do
        %w[stylex defaultx click href call accTitlex accDescrx].each do |id|
          expect(edge_links("A #{id}@--> B")).to eq(%w[A>B]), id
        end
      end
    end

    it "refuses an id that starts like a dotted link" do
      expect { parse_flowchart("A ..-x@--> B") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "takes an id glued to the & before it" do
      expect(edge_links("A &x@--> B")).to eq(%w[A>B])
    end

    it "keeps a glued & in the captured id" do
      expect(node_ids("A &x@--> B\nx@{ animate: true }"))
        .to eq(%w[A B x])
      expect(node_ids("A &x@--> B\n&x@{ animate: true }"))
        .to eq(%w[A B])
    end

    it "refuses an id with a quote in it" do
      expect { parse_flowchart('A x"y@--> B') }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses line whitespace inside an id" do
      expect { parse_flowchart("A x\u00A0y@--> B") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses a metadata opener where an id would start" do
      expect { parse_flowchart("A @{x@--> B") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses an id that starts on the line after its source" do
      expect { parse_flowchart("A\ne1@--> B") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "still takes a link on the line after its source" do
      expect(edge_links("A\n--> B")).to eq(%w[A>B])
    end

    it "refuses an id written flush against a shaped source" do
      expect { parse_flowchart("A[x]e1@--> B") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses an id after a source with a properties block" do
      expect { parse_flowchart("A@{ shape: circle } e1@--> B") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "takes a no-break space between the @ and the link" do
      expect(edge_links("A e1@\u00A0--> B")).to eq(%w[A>B])
    end

    it "takes a byte order mark between the @ and the link" do
      expect(edge_links("A e1@\uFEFF--> B")).to eq(%w[A>B])
    end

    it "takes a comment line between the @ and the link" do
      expect(edge_links("A e1@\n%% note\n--> B")).to eq(%w[A>B])
    end

    it "refuses a comment on the same line after the @" do
      expect { parse_flowchart("A e1@%% note\n--> B") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    %w[<--> o--o x--x ~~~].each do |link|
      it "takes an id before a #{link} link" do
        source = "A e1@#{link} B"

        expect([node_ids(source), edge_links(source)]).to eq([%w[A B], %w[A>B]])
      end
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
    it "keeps the edge that ends at it without creating a node" do
      source = "A e1@--> B\nC --> e1@{ shape: rect }"

      expect([node_ids(source), edge_links(source)])
        .to eq([%w[A B C], %w[A>B C>e1]])
    end

    it "keeps the edges that start at a grouped one without creating a node" do
      source = "A e1@--> B\nC & e1@{ shape: rect } --> D"

      expect([node_ids(source), edge_links(source)])
        .to eq([%w[A B C D], %w[A>B C>D e1>D]])
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
