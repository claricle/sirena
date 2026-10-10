# frozen_string_literal: true

require "spec_helper"

# Expected lines are what mmdc drew for the same text (references 020, 022
# and a hand-run `wrap:` message with an over-long word), measured at 16px.
RSpec.describe Sirena::Layout::Sequence::TextWrap do
  let(:long) do
    "Hello Bob, how are you? If you are not available right now, I can " \
      "leave you a message. Please get back to me as soon as you can!"
  end

  it "breaks a long message into the four lines mmdc draws" do
    expect(described_class.lines(long, 215, 16)).to eq(
      ["Hello Bob, how are you? If you", "are not available right now, I can",
       "leave you a message. Please get", "back to me as soon as you can!"],
    )
  end

  it "cuts a word wider than the limit with hyphens" do
    word = "Supercalifragilisticexpialidocious_" * 2

    expect(described_class.lines("#{word} and then", 225, 16).first(2)).to eq(
      ["Supercalifragilisticexpialidocious_S-",
       "upercalifragilisticexpialidocious_"],
    )
  end

  it "leaves text that holds a <br> as the source wrote it" do
    expect(described_class.lines("a<br>b c", 10, 16)).to eq(["a", "b c"])
  end

  it "drops the blanks between words" do
    expect(described_class.lines("a   b", 215, 16)).to eq(["a b"])
  end

  it "gives no lines for blank text" do
    expect(described_class.lines("   ", 215, 16)).to eq([])
  end

  {
    "wrap: on" => ["wrap: x", false, true],
    "nowrap: off" => ["nowrap: x", true, false],
    "no prefix, global on" => ["x", true, true],
    "no prefix, global off" => ["x", false, false],
  }.each do |name, (source, global, expected)|
    it "decides #{name}" do
      expect(described_class.wrapped?(source, global)).to be(expected)
    end
  end

  it "takes the prefix off the body" do
    expect(described_class.body("  nowrap:  x y")).to eq("x y")
  end
end
