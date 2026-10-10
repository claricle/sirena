# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/kanban"

RSpec.describe Sirena::Parser::Grammars::Kanban do
  it "preserves the public metadata entry capture shape" do
    tree = described_class.new.metadata_entry.parse("priority : high")

    expect(tree).to eq(
      key: "priority",
      value: { unquoted: "high" },
    )
  end
end
