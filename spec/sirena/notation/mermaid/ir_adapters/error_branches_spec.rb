# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/error"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Error do
  it "uses noncolliding default identities" do
    diagram = Sirena::Diagram::Error.new(message: "Unavailable")
    ir = described_class.call(diagram)
    message = ir.items.first

    expect([ir.valid?, ir.id, message.id, message.label])
      .to eq([true, "error", "message", "Unavailable"])
  end
end
