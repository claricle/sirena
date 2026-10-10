# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/info"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Info do
  it "uses noncolliding defaults for a hidden information flag" do
    ir = described_class.call(Sirena::Diagram::Info.new)
    flag = ir.values.first

    expect([ir.valid?, ir.id, flag.id, flag.value.value])
      .to eq([true, "info", "show_information", false])
  end
end
