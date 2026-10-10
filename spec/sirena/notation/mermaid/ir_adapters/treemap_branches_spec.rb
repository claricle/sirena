# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/treemap"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Treemap do
  subject(:ir) { described_class.call(diagram) }

  let(:diagram) do
    Sirena::Diagram::Treemap.new.tap do |treemap|
      treemap.add_class_def("emphasis", "font-weight:bold")
    end
  end

  it "does not invent colors for unrelated class properties" do
    expect([ir.valid?, ir.values]).to eq([true, []])
  end
end
