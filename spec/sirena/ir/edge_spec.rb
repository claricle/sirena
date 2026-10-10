# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Edge do
  it "accepts an edge with both endpoints" do
    expect(ir_messages(described_class, id: "e", source_id: "a",
                                        target_id: "b")).to be_empty
  end

  it "rejects an empty source" do
    expect(ir_messages(described_class, id: "e", source_id: "",
                                        target_id: "b"))
      .to include("source_id must be nonempty")
  end

  it "rejects a missing target" do
    expect(ir_messages(described_class, id: "e", source_id: "a"))
      .to include("target_id must be nonempty")
  end
end
