# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/block"

RSpec.describe Sirena::Parser::Block do
  subject(:style) { described_class.new.parse(source).styles.first }

  let(:source) { "block-beta\n  A\n  style A stroke:#333\n" }

  it "attaches a stroke declaration to its target" do
    expect([style.block_id, style.stroke]).to eq(["A", "#333"])
  end
end
