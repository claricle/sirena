# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render pie validity" do
    [
      "pie\n  \\t\"GitHub\" \\t : \\t 100\n",
      "pie\n  \\ttitle sample title\n",
      "pie\n  \"GitHub\"\\t:\\t100\n",
    ].each do |source|
      it "refuses a literal backslash-t as whitespace in #{source.inspect}" do
        expect { described_class.render(source) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end
    end

    [
      "pie\n  \"GitHub\"\t:\t100\n",
      "pie\n  \ttitle sample title\n  \"A\" : 1\n",
      "pie\n  \"GitHub\" : 100\n  \"GitLab\" : 50\n",
    ].each do |source|
      it "still renders real whitespace in #{source.inspect}" do
        expect(described_class.render(source)).to start_with("<svg")
      end
    end
  end
end
