# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/grammars/quadrant"

RSpec.describe Sirena::Parser::Grammars::Quadrant do
  subject(:tree) { described_class.new.parse(source) }

  let(:source) { "quadrantChart\nclassDef priority fill:#f96\nLaunch:::priority: [0.2, 0.8]\n" }

  it "retains class identifiers in definitions and references" do
    expect([tree[1][:class_name].to_s, tree[2][:class_ref].to_s]).to eq(["priority", ":::priority"])
  end
end
