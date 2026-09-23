# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart do
  include FlowchartParserHelpers

  let(:header) { "graph TD\nA-->B\n" }

  describe "a linkStyle statement" do
    [
      "linkStyle 0 stroke-width:1px;",
      "linkStyle 0 stroke:red,stroke-width:2px",
      "linkStyle default stroke:red",
      "linkStyle 0 interpolate basis",
      "linkStyle\u00A00 stroke:red",
      "linkStyle 0\u00A0stroke:red",
      "linkStyle 0 interpolate basis  stroke:red,stroke-width:2px",
      "linkStyle default interpolate basis stroke:red",
      "linkStyle 0 stroke:defaults",
      "linkStyle 0 stroke:x-default",
      "linkStyle 0 stroke:x9default",
      "linkStyle 0 stroke:#f00,fill:red;",
      "linkStyle 0 stroke:#f00 ;",
      "linkStyle 0 border-style:x,stroke:#f00;",
      # `classDef` gets the same last-`;` exemption as `style`, applied
      # right after it.
      "linkStyle 0 xclassDef:x:#f00;",
      # mermaid strips over the whole line, so a `classDef` split across
      # the curve name and the styles after it is exempt too.
      "linkStyle 0 interpolate xclassDef y:#f00;"
    ].each do |statement|
      it "takes #{statement.inspect} and keeps the edge" do
        expect(parse_flowchart(statement, header: header).edges.size).to eq(1)
      end
    end

    it "takes a second edge's index once that edge is written" do
      source = "graph TD\nA-->B\nB-->C\nlinkStyle 0,1 stroke:red\n"

      expect(described_class.new.parse(source).edges.size).to eq(2)
    end

    # The grammar stops at the space, column 13. An out-of-bounds error
    # instead would mean the space got through to the index check.
    ["linkStyle 0, 1 stroke:red", "linkStyle 0 ,1 stroke:red",
     "linkStyle 0\u00A0,1 stroke:red", "linkStyle 0,\u00A01 stroke:red"].each do |statement|
      it "refuses the space around the comma in #{statement.inspect}" do
        source = "graph TD\nA-->B\nB-->C\n#{statement}\n"

        expect { described_class.new.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /line 4, column 13/)
      end
    end

    # mermaid reads both words as keywords wherever they sit in the
    # style text; only a leading `interpolate <curve>` is allowed.
    ["linkStyle 0 interpolate", "linkStyle 0 interpolate  basis",
     "linkStyle 0 stroke:red interpolate basis", "linkStyle 0 interpolate:red",
     "linkStyle 0 interpolate interpolate", "linkStyle 0 default",
     "linkStyle 0 stroke:default", "linkStyle 0 interpolate basis default",
     "linkStyle 0 stroke:#f00;default", "linkStyle 0 stroke:1default",
     "linkStyle 0 stroke:#interpolate",
     "linkStyle 0 stroke:red default"].each do |statement|
      it "refuses the keyword in #{statement.inspect}" do
        expect { parse_flowchart(statement, header: header) }
          .to raise_error(Sirena::Parser::ParseError,
                          /linkStyle cannot use `(interpolate|default)`/)
      end
    end

    # Only a lowercase `style` or a `classDef` run gets its last `;`
    # dropped before mermaid turns `#name;` into an entity.
    ["linkStyle 0 stroke:#f00;", "linkStyle 0 #f00;",
     "linkStyle 0 interpolate #f00;", "linkStyle 0 stroke:red,fill:#f00;",
     "linkStyle 0 stroke:#f00;B"].each do |statement|
      it "refuses the entity in #{statement.inspect}" do
        expect { parse_flowchart(statement, header: header) }
          .to raise_error(Sirena::Parser::ParseError, /HTML entity/)
      end
    end

    # An edge id, an `&` group and a chain each add ordinary edges; an
    # `e1@{...}` block addresses an edge and adds none.
    {
      "A e1@--> B" => 1, "A e1@--> B\ne1@{animate: true}" => 1,
      "A & B --> C" => 2, "A-->B-->C" => 2
    }.each do |edges, count|
      it "counts #{count} edges in #{edges.inspect}" do
        styled = "graph TD\n#{edges}\nlinkStyle #{count - 1} stroke:red\n"
        beyond = "graph TD\n#{edges}\nlinkStyle #{count} stroke:red\n"

        expect(described_class.new.parse(styled).edges.size).to eq(count)
        expect { described_class.new.parse(beyond) }
          .to raise_error(Sirena::Parser::ParseError, /index #{count} /)
      end
    end

    it "refuses the zero-padded index 00" do
      expect { parse_flowchart("linkStyle 00 stroke:red", header: header) }
        .to raise_error(Sirena::Parser::ParseError, /index 00 /)
    end

    it "takes `default` before any edge is written, it is not an index" do
      source = "graph TD\nlinkStyle default stroke:red\nA-->B\n"

      expect(described_class.new.parse(source).edges.size).to eq(1)
    end

    ["linkStyle 1 stroke:red", "linkStyle 0,1 stroke:red"].each do |statement|
      it "refuses #{statement.inspect} when only edge 0 exists" do
        expect { parse_flowchart(statement, header: header) }
          .to raise_error(Sirena::Parser::ParseError, /out of bounds/)
      end
    end

    it "refuses an index written before any edge" do
      expect do
        described_class.new.parse("graph TD\nlinkStyle 0 stroke:red\nA-->B\n")
      end.to raise_error(Sirena::Parser::ParseError, /index 0/)
    end
  end

  # `linkStyle 0` on a one-edge diagram is the bucket; `linkStyle 1` on the
  # same diagram is its mirror, which the oracle marks invalid.
  describe "the flowchart corpus cases that carry a linkStyle" do
    cases = Dir[File.join(__dir__, "../../mermaid/flowchart/*.mmd")]
      .select { |f| File.read(f).include?("linkStyle") }
    valid, invalid = cases.partition { |f| File.read(f).include?("linkStyle 0 ") }

    valid.each do |path|
      it "renders #{File.basename(path, '.mmd')}" do
        expect(Sirena::Engine.new.render(File.read(path))).to include("<svg")
      end
    end

    invalid.each do |path|
      it "refuses #{File.basename(path, '.mmd')}" do
        expect { Sirena::Engine.new.render(File.read(path)) }
          .to raise_error(Sirena::Parser::ParseError, /out of bounds/)
      end
    end
  end
end
