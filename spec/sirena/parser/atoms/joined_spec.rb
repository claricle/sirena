# frozen_string_literal: true

require "spec_helper"
require "parslet"
require "sirena/parser/atoms/joined"

RSpec.describe Sirena::Parser::Atoms::Joined do
  include Parslet

  let(:atom) { described_class.new((str("a") | str("\n")).repeat) }

  it "returns everything the inner atom consumed as one slice" do
    expect(atom.parse("a\naa\n")).to be_a(Parslet::Slice).and eq("a\naa\n")
  end

  it "reports the position where the inner atom started" do
    parser = str(">") >> described_class.new(str("a").repeat).as(:run)

    expect(parser.parse(">aaa")[:run].offset).to eq(1)
  end

  it "joins nested pieces in order" do
    nested = described_class.new((str("a") >> str("b").maybe).repeat)

    expect(nested.parse("abaab").to_s).to eq("abaab")
  end

  it "passes a failure of the inner atom through" do
    expect { described_class.new(str("a")).parse("b", prefix: true) }
      .to raise_error(Parslet::ParseFailed)
  end

  it "refuses an inner atom that captures, rather than drop its text" do
    captured = described_class.new(str("a").as(:piece).repeat)

    expect { captured.parse("aaa") }
      .to raise_error(ArgumentError, /captured Hash/)
  end

  it "prints as the atom it wraps" do
    expect(described_class.new(str("a")).inspect).to eq("'a'")
  end

  it "parenthesizes the atom it wraps where precedence needs it" do
    sequence = str("x") >> described_class.new(str("a") | str("b"))

    expect(sequence.inspect).to eq("'x' ('a' / 'b')")
  end

  it "joins many pieces in linear time" do
    wide = described_class.new((str("a") >> str("\n")).repeat)
    input = "a\n" * 150_000

    expect { Timeout.timeout(5) { wide.parse(input) } }.not_to raise_error
  end
end
