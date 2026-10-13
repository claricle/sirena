# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence::ActorGaps do
  let(:instance) { described_class.allocate }
  let(:children) { [{ id: "A", width: 100 }, { id: "B", width: 150 }] }

  it "preserves the required argument arity" do
    expect(described_class.instance_method(:initialize).arity).to eq(4)
  end

  it "keeps the default actor gap unchanged" do
    gaps = described_class.new(children, [], nil, font_size: 16)
    expect(gaps.extra_after("A")).to eq(0)
  end

  it "keeps default created-participant storage independent" do
    first = described_class.new(children, [], nil, font_size: 16)
    second = described_class.new(children, [], nil, font_size: 16)
    first.instance_variable_get(:@created) << "B"
    expect(second.extra_after("A")).to eq(0)
  end

  context "with a created participant and explicit wrapping" do
    subject(:gaps) do
      described_class.new(children, [], [], font_size: 16,
                                            wrap: true, creations: creations)
    end

    let(:creations) { Struct.new(:ids).new(["B"]) }

    it "keeps the created actor's half-box spacing" do
      expect(gaps.extra_after("A")).to eq(75)
    end
  end

  {
    "one unknown keyword" =>
      [3, { font_size: 16, unknown: 1 }, "unknown keyword: :unknown"],
    "ordered unknown keywords" =>
      [3, { font_size: 16, second: 1, first: 2 },
       "unknown keywords: :second, :first"],
    "a string key matching a supported symbol" =>
      [3, { font_size: 16, "wrap" => true }, 'unknown keyword: "wrap"'],
    "mixed string and symbol keys" =>
      [3, { font_size: 16, second: 1, "creations" => nil, first: 2 },
       'unknown keywords: :second, "creations", :first'],
    "a missing font size" =>
      [3, {}, "missing keyword: :font_size"],
    "a missing font size before unknown-key validation" =>
      [3, { unknown: 1 }, "missing keyword: :font_size"],
    "too few positional arguments" =>
      [2, { font_size: 16 },
       "wrong number of arguments (given 2, " \
       "expected 3; required keyword: font_size)"],
    "too many positional arguments" =>
      [4, { font_size: 16 },
       "wrong number of arguments (given 4, " \
       "expected 3; required keyword: font_size)"],
  }.each do |description, (count, keywords, message)|
    context "with #{description}" do
      let(:failure) do
        instance.send(:initialize, *Array.new(count), **keywords)
      rescue ArgumentError => e
        e
      end

      before { failure }

      it "preserves the native argument error" do
        expect(failure).to be_a(ArgumentError)
          .and(have_attributes(message: message))
      end

      it "rejects the call before changing instance state" do
        expect(instance.instance_variables).to be_empty
      end
    end
  end
end
