# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render sequence validity" do
    [
      'Alice \\\\|- John: Hi',
      'Alice \\\\|-John: Hi',
      'Alice \\\\\\|- John: Hi',
    ].each do |line|
      it "refuses the escape-fused arrow #{line.inspect}" do
        expect { described_class.render("sequenceDiagram\n#{line}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "refuses the corpus case with the fused reversed arrow" do
      path = "spec/mermaid/sequence/sequencediagram_spec-97601112.mmd"

      expect { described_class.render(File.read(path)) }
        .to raise_error(Sirena::Parser::ParseError)
    end

    ['Alice \\|- John: Hi', 'Alice \\\\- John: Hi'].each do |line|
      it "renders the real reversed arrow #{line.inspect}" do
        svg = described_class.render("sequenceDiagram\n#{line}\n")

        expect(svg).to include(">Hi</text>")
      end
    end
  end
end
