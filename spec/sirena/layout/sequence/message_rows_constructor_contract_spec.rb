# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence::MessageRows do
  let(:instance) { described_class.allocate }
  let(:edges) do
    [{ sources: ["A"], targets: ["A"],
       metadata: { message_source: "Hello" } }]
  end

  it "preserves the required argument arity" do
    expect(described_class.instance_method(:initialize).arity).to eq(3)
  end

  it "keeps the default wrapping disabled" do
    rows = described_class.new(edges, {}, font_size: 16)
    expect(rows.wrap?).to be(false)
  end

  it "keeps default closer storage independent" do
    first = described_class.new(edges, {}, font_size: 16)
    second = described_class.new(edges, {}, font_size: 16)
    first.instance_variable_get(:@closers) << 0
    expect(second.total_extra).to eq(30)
  end

  it "keeps default creator storage independent" do
    first = described_class.new(edges, {}, font_size: 16)
    second = described_class.new(edges, {}, font_size: 16)
    first.instance_variable_get(:@creators) << 0
    expect(second.total_extra).to eq(30)
  end

  context "with explicit row settings" do
    subject(:rows) do
      described_class.new(edges, {}, font_size: 16, wrap: true,
                                     closers: [0], creators: [0])
    end

    it "keeps wrapping enabled" do
      expect(rows.wrap?).to be(true)
    end

    it "keeps frame and creator spacing unchanged" do
      expect(rows.total_extra).to eq(92.5)
    end
  end

  {
    "one unknown keyword" =>
      [2, { font_size: 16, unknown: 1 }, "unknown keyword: :unknown"],
    "ordered unknown keywords" =>
      [2, { font_size: 16, second: 1, first: 2 },
       "unknown keywords: :second, :first"],
    "a string key matching a supported symbol" =>
      [2, { font_size: 16, "closers" => [] }, 'unknown keyword: "closers"'],
    "mixed string and symbol keys" =>
      [2, { font_size: 16, second: 1, "creators" => [], first: 2 },
       'unknown keywords: :second, "creators", :first'],
    "a missing font size" =>
      [2, {}, "missing keyword: :font_size"],
    "a missing font size before unknown-key validation" =>
      [2, { unknown: 1 }, "missing keyword: :font_size"],
    "too few positional arguments" =>
      [1, { font_size: 16 },
       "wrong number of arguments (given 1, " \
       "expected 2; required keyword: font_size)"],
    "too many positional arguments" =>
      [3, { font_size: 16 },
       "wrong number of arguments (given 3, " \
       "expected 2; required keyword: font_size)"],
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
