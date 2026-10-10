# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/treemap"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Treemap do
  let(:diagram) do
    Sirena::Diagram::Treemap.new.tap do |treemap|
      treemap.add_class_def("tint", "fill:red;stroke-width:2")
      treemap.add_class_def("plain", "stroke-width:2")
    end
  end

  it "emits a style value only for the colours a class sets" do
    ids = described_class.call(diagram).values.map(&:id)

    expect(ids).to eq(["style_tint_fill"])
  end
end
