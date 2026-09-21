# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  include FlowchartParserHelpers

  let(:header) { "graph TD\nA-->B\n" }

  describe "a linkStyle statement" do
    [
      "linkStyle 0 stroke-width:1px;",
      "linkStyle 0 stroke:red,stroke-width:2px",
      "linkStyle default stroke:red",
      "linkStyle 0 interpolate basis"
    ].each do |statement|
      it "takes #{statement.inspect} and keeps the edge" do
        expect(parse_flowchart(statement, header: header).edges.size).to eq(1)
      end
    end

    it "takes a second edge's index once that edge is written" do
      source = "graph TD\nA-->B\nB-->C\nlinkStyle 0,1 stroke:red\n"

      expect(described_class.new.parse(source).edges.size).to eq(2)
    end

    it "takes no space after the comma of a list of indices" do
      source = "graph TD\nA-->B\nB-->C\nlinkStyle 0, 1 stroke:red\n"

      expect { described_class.new.parse(source) }
        .to raise_error(Sirena::Parser::ParseError)
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
        expect { Sirena::Engine.new.render(File.read(path)) }
          .not_to raise_error
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
