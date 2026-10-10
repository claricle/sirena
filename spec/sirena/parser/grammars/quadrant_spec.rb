# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/grammars/quadrant"

RSpec.describe Sirena::Parser::Grammars::Quadrant do
  subject(:tree) { described_class.new.parse(source) }

  let(:source) do
    "quadrantChart\nclassDef priority fill:#f96\n" \
      "Launch:::priority: [0.2, 0.8]\n"
  end

  it "retains class identifiers in definitions and references" do
    names = [tree[1][:class_name].to_s, tree[2][:class_ref].to_s]

    expect(names).to eq(["priority", ":::priority"])
  end
end
