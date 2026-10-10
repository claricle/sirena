# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Engine do
  subject(:texts) do
    svg = described_class.new.render(source)
    svg.scan(%r{<text[^>]*>([^<]*)</text>}).flatten
  end

  let(:source) do
    <<~MMD
      C4Context
      title System Context diagram
      Person(cust, "Customer", "A customer")
      System_Ext(mail, "Mail", "Sends mail")
    MMD
  end

  it "draws the stereotype above each name, then the title" do
    expect(texts).to eq(
      ["&lt;&lt;person&gt;&gt;", "Customer", "A customer",
       "&lt;&lt;external_system&gt;&gt;", "Mail", "Sends mail",
       "System Context diagram"],
    )
  end

  it "draws the stereotype in 12px italic" do
    svg = described_class.new.render(source)
    expect(svg)
      .to match(/font-size="12(\.0)?"[^>]*font-style="italic"[^>]*>&lt;/)
  end

  context "without a title" do
    let(:source) { "C4Context\nPerson(cust, \"Customer\", \"A customer\")\n" }

    it "draws only the element captions" do
      expect(texts).to eq(
        ["&lt;&lt;person&gt;&gt;", "Customer", "A customer"],
      )
    end
  end
end
