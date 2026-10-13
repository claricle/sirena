# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence/message_wrap"

RSpec.describe Sirena::Notation::PlantUML::Sequence::MessageWrap do
  let(:measure) { ->(text) { text.length * 10.0 } }
  let(:actual_lines) do
    [nil, 40].flat_map do |limit|
      wrapper = described_class.new(limit, measure)
      cases.map { |label, _expected| wrapper.lines(label) }
    end
  end

  context "with escaped line breaks" do
    let(:cases) do
      [
        ["one\\ntwo", ["one", "two"]],
        ["one\\\\ntwo", ["one\\ntwo"]],
        ["one\\\\\\ntwo", ["one\\", "two"]],
      ]
    end

    it "decodes line breaks without consuming escaped backslashes" do
      expect(actual_lines).to eq(cases.map(&:last) * 2)
    end
  end

  context "with empty explicit rows" do
    let(:cases) do
      [
        ["\\none", ["", "one"]],
        ["one\\n", ["one", ""]],
        ["one\\n\\ntwo", ["one", "", "two"]],
        ["\\n", ["", ""]],
        ["", [""]],
      ]
    end

    it "preserves empty rows around explicit line breaks" do
      expect(actual_lines).to eq(cases.map(&:last) * 2)
    end
  end

  context "when the label already contains newlines" do
    let(:cases) { [["\none\n\ntwo\n", ["", "one", "", "two", ""]]] }

    it "preserves explicit rows" do
      expect(actual_lines).to eq(cases.map(&:last) * 2)
    end
  end

  it "wraps and measures each explicit row independently" do
    wrapper = described_class.new(50, measure)
    label = "aa bb\\ncc dd ee"

    expect([wrapper.lines(label), wrapper.width(label)])
      .to eq([["aa bb", "cc dd", "ee"], 50.0])
  end
end
