# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render sankey validity" do
    {
      "a two-node cycle" => "A,B,1\nB,A,1",
      "a self-flow" => "A,A,1",
      "a longer cycle behind a tail" => "S,A,1\nA,B,1\nB,C,1\nC,A,1",
    }.each do |name, flows|
      it "refuses #{name}" do
        expect { described_class.render("sankey-beta\n#{flows}\n") }
          .to raise_error(Sirena::Parser::ParseError, /Circular link/)
      end
    end

    it "refuses the corpus proto cycle" do
      path = "spec/mermaid/sankey/" \
             "parses_csv_with_sankey_beta_syntax-ac5bf38a.mmd"

      expect { described_class.render(File.read(path)) }
        .to raise_error(Sirena::Parser::ParseError, /Circular link/)
    end

    it "renders a diamond that converges without a cycle" do
      source = "sankey-beta\nA,B,1\nA,C,1\nB,D,1\nC,D,1\n"

      expect(described_class.render(source)).to start_with("<svg")
    end
  end
end
