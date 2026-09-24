# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::Flowchart do
  let(:parser) { described_class.new }

  describe '#parse with a flowchart-elk header' do
    it 'parses the body as an ordinary flowchart' do
      source = "flowchart-elk TD\n  A-->B"
      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::Flowchart)
      expect(diagram.direction).to eq('TD')
      expect(diagram.nodes.length).to eq(2)
      expect(diagram.edges.length).to eq(1)
    end

    # The header used to be rewritten out of the source before parsing
    # (`flowchart-elk` -> `flowchart`), 4 characters shorter, so a parse
    # error on a `flowchart-elk` diagram quoted the rewritten line and
    # pointed 4 columns left of the real failure. The grammar now matches
    # `flowchart-elk` directly, so the error must quote the SOURCE the
    # caller submitted, at the SOURCE's own column. Codex round-2 finding
    # 3 (ffaabf5d).
    it 'points a parse error at the caller\'s own source and column' do
      source = %(flowchart-elk TD;"unterminated\n)

      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      ) do |error|
        expect(error.message).to include('flowchart-elk TD;"unterminated')
        expect(error.message).to include('column 18')
      end
    end
  end
end
