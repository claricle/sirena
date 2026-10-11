# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart do
  it "refuses an anchor that sits on a later line than its tag" do
    source = "graph TD\nA@{\nlabel: !!str\n  &a x\n}\n"

    expect { described_class.new.parse(source) }
      .to raise_error(Sirena::Parser::ParseError, /Ambiguous anchor: a/)
  end
end
