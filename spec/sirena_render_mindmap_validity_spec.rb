# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  describe ".render mindmap validity" do
    {
      "a header with no root and no line break" => "mindmap",
      "an unterminated square shape" => "mindmap\n    id1[\\",
      "an unterminated round shape" => "mindmap\n  root\n    a(b",
      "an unterminated circle shape" => "mindmap\n  a((b",
    }.each do |name, source|
      it "refuses #{name}" do
        expect { described_class.render(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    [
      "mindmap\n",
      "mindmap   ",
      "mindmap\n  root[text]",
      "mindmap\n  root((text))",
      "mindmap\n  root\n    child (note)",
    ].each do |source|
      it "still renders #{source.inspect}" do
        expect(described_class.render(source)).to start_with("<svg")
      end
    end
  end
end
