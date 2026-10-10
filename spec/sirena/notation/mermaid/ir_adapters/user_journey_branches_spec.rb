# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/user_journey"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::UserJourney do
  subject(:ir) { described_class.call(diagram) }

  let(:diagram) do
    diagram = Sirena::Diagram::UserJourney.new(id: "")
    diagram.define_singleton_method(:acc_title) { nil }
    diagram.define_singleton_method(:acc_description) { nil }
    diagram
  end

  it "uses the default identity and omits unset accessibility fields" do
    expect([ir.valid?, ir.id, ir.accessibility_title,
            ir.accessibility_description])
      .to eq([true, "user_journey", nil, nil])
  end

  context "when the root collides with a generated section identity" do
    let(:diagram) do
      section = Sirena::Diagram::JourneySection.new(name: "Discover")
      Sirena::Diagram::UserJourney.new(
        id: "section_0", sections: [section],
      )
    end

    it "keeps generated section identities collision-free" do
      expect(ir.nodes.map(&:id)).to eq(["section_0_2"])
    end
  end
end
