# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence/message_wrap"

RSpec.describe Sirena::Notation::PlantUML::Sequence::MessageWrap do
  let(:measure) { ->(text) { text.length * 10.0 } }

  it "decodes escaped line breaks without consuming escaped backslashes" do
    cases = [
      [1, ["one", "two"]],
      [2, ["one\\ntwo"]],
      [3, ["one\\", "two"]],
    ]

    [nil, 40].each do |limit|
      wrapper = described_class.new(limit, measure)
      cases.each do |slashes, expected|
        backslashes = "\\" * slashes
        label = "one#{backslashes}ntwo"

        expect(wrapper.lines(label)).to eq(expected)
      end
    end
  end

  it "preserves empty rows around explicit line breaks" do
    cases = [
      ["\\none", ["", "one"]],
      ["one\\n", ["one", ""]],
      ["one\\n\\ntwo", ["one", "", "two"]],
      ["\\n", ["", ""]],
    ]

    [nil, 40].each do |limit|
      wrapper = described_class.new(limit, measure)
      cases.each do |label, expected|
        expect(wrapper.lines(label)).to eq(expected)
      end
    end
  end

  it "preserves explicit rows when the label already contains newlines" do
    [nil, 40].each do |limit|
      wrapper = described_class.new(limit, measure)

      expect(wrapper.lines("\none\n\ntwo\n"))
        .to eq(["", "one", "", "two", ""])
    end
  end

  it "wraps and measures each explicit row independently" do
    wrapper = described_class.new(50, measure)
    label = "aa bb\\ncc dd ee"

    expect(wrapper.lines(label)).to eq(["aa bb", "cc dd", "ee"])
    expect(wrapper.width(label)).to eq(50.0)
  end
end
