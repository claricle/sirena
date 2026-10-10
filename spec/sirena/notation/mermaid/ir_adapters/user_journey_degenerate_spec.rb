# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/user_journey"
require "sirena/diagram/user_journey"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::UserJourney do
  let(:diagram) { Sirena::Diagram::UserJourney.new(id: "", sections: []) }
  let(:ir) { described_class.call(diagram) }

  it "falls back to the type name for an empty diagram id" do
    expect(ir.id).to eq("user_journey")
  end

  it "reads a nil accessibility title as absent" do
    diagram.define_singleton_method(:acc_title) { nil }

    expect(ir.accessibility_title).to be_nil
  end
end
