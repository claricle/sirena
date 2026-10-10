# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence/message_wrap"

RSpec.describe Sirena::Notation::PlantUML::Sequence::MessageWrap do
  let(:measure) { ->(text) { text.length * 10.0 } }

  def wrap(limit)
    described_class.new(limit, measure)
  end

  it "never wraps without a limit" do
    expect(wrap(nil).lines("aaa bbb ccc")).to eq(["aaa bbb ccc"])
  end

  it "fills a line with words while they fit" do
    expect(wrap(80).lines("aa bb cc dd")).to eq(["aa bb cc", "dd"])
  end

  it "keeps a word wider than the limit on a line of its own" do
    expect(wrap(30).lines("a bbbbbb c")).to eq(["a", "bbbbbb", "c"])
  end

  it "measures the widest wrapped line" do
    expect(wrap(80).width("aa bb cc dd")).to eq(80.0)
  end
end
