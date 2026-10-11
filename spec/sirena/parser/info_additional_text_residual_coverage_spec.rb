# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/info"

RSpec.describe Sirena::Parser::Info do
  it "refuses additional header text, as Mermaid's lexer does" do
    expect { described_class.new.parse("info ignored words") }
      .to raise_error(Sirena::Parser::ParseError)
  end
end
