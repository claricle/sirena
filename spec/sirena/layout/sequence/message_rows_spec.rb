# frozen_string_literal: true

require "spec_helper"

# One two-word message between actors 200 apart. mmdc breaks it when the
# words fill the line: 213 wide breaks only below 213, 216 below 216.
# The limit is the room between the actors less the activation edges (2)
# and the head insets (3 each), plus 20: 215 for a filled head.
RSpec.describe Sirena::Layout::Sequence::MessageRows do
  let(:short) { "aa #{'m' * 16}" }
  let(:wide) { "#{'a' * 13} #{'m' * 10}" }
  let(:positions) { { "A" => { center_x: 0 }, "B" => { center_x: 200 } } }

  def rows_for(text, style: "filled", side: "target", wrap: true)
    meta = { message_source: text, head_style: style, head_side: side }
    edge = { sources: ["A"], targets: ["B"], metadata: meta }
    described_class.new([edge], positions, font_size: 16, wrap: wrap)
  end

  {
    "filled" => ["filled", "target", [1, 2]],
    "cross" => ["cross", "target", [1, 2]],
    "open" => ["none", "target", [1, 1]],
    "stick" => ["stick_top", "target", [1, 1]],
    "both ends" => ["filled", "both", [2, 2]],
    "reversed half" => ["half_top", "source", [1, 2]],
    "reversed stick" => ["stick_top", "source", [1, 1]],
  }.each do |name, (style, side, counts)|
    it "wraps a #{name} arrow into #{counts.inspect} lines" do
      rows = [short, wide].map { |t| rows_for(t, style: style, side: side) }

      expect(rows.map { |row| row.lines(0).length }).to eq(counts)
    end
  end

  it "does not wrap when the diagram does not" do
    expect(rows_for(wide, wrap: false).lines(0)).to eq([wide])
  end

  it "adds 17 for every line past the first" do
    expect(rows_for("a<br>b<br>c", wrap: false).extra(0)).to eq(34)
  end

  it "adds nothing for one line" do
    expect(rows_for("a", wrap: false).extra(0)).to eq(0)
  end

  it "counts a message's growth below it, not above it" do
    rows = rows_for("a<br>b", wrap: false)

    expect([rows.extra_before(0), rows.extra_through(0)]).to eq([0, 17])
  end

  it "decodes a character reference in a drawn line" do
    expect(rows_for("I #9829; you", wrap: false).lines(0)).to eq(["I ♥ you"])
  end

  it "has no lines for an index it has no message for" do
    expect(rows_for("a").lines(nil)).to eq([])
  end
end
