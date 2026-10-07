# frozen_string_literal: true

require "spec_helper"

module TextMeasurementSpecHelpers
  def width(text, size: 100, **)
    Sirena::TextMeasurement.measure(text, font_size: size, **)[:width]
  end
end

RSpec.describe Sirena::TextMeasurement do
  include TextMeasurementSpecHelpers

  describe ".measure" do
    let(:undecodable) do
      [
        "a\xFFb",
        "caf\xE9".b,
        (+"caf\xE9").force_encoding("ISO-8859-1"),
        (+"ab").force_encoding("UTF-7"),
        (+"a\xFFb").force_encoding("UTF-7"),
        "ab".encode("UTF-16LE"),
        (+"\xD7\xC2\xA8").force_encoding("CESU-8"),
        (+"\xD7\xC2\xA8").force_encoding("UTF8-SoftBank"),
      ]
    end

    {
      "A" => 66.7,
      "W" => 94.4,
      "@" => 101.5,
      "i" => 22.2,
      " " => 27.8,
      "\t" => 27.8,
      "é" => 55.6,
      "€" => 55.6,
    }.each do |char, expected|
      it "measures #{char.inspect} at its Arial advance" do
        expect(width(char)).to be_within(0.001).of(expected)
      end
    end

    it "matches the width Chrome reports for a wide-glyph label" do
      expect(width("|WWWWWWWW|", size: 12)).to be_within(0.05).of(96.84375)
    end

    # SVG collapses the newline inside one <text> to a space, so the box
    # must fit the whole string, not its widest line.
    it "measures a newline, tab and carriage return as one space each" do
      expect(%W[a\nb a\tb a\rb].map { |text| width(text) })
        .to all(eq(width("a b")))
    end

    it "measures a newline as one monospace cell" do
      expect(width("a\nb", monospace: true))
        .to eq(width("a b", monospace: true))
    end

    it "measures an empty or nil text as zero" do
      expect([width(""), width(nil)]).to eq([0.0, 0.0])
    end

    it "scales linearly with the font size" do
      expect(width("Hello", size: 28))
        .to be_within(0.001).of(width("Hello", size: 14) * 2)
    end

    {
      "Han" => "中",
      "Hangul" => "한",
      "Hiragana" => "あ",
      "Hebrew" => "א",
    }.each do |script, char|
      it "measures a #{script} codepoint outside the table as one em" do
        expect(width(char)).to eq(100.0)
      end
    end

    # Summed from Arial's hmtx table with ttfunk.
    it "measures Cyrillic and Greek at their Arial advances" do
      rounded = [width("Привет"), width("Αβγ")].map { |w| w.round(1) }
      expect(rounded).to eq([337.9, 174.2])
    end

    {
      "U+FDFA" => ["ﷺ", 125.0],
      "U+FDFB" => ["ﷻ", 105.0],
      "U+FDFC" => ["﷼", 125.0],
      "U+FDFD" => ["﷽", 650.0],
      "an emoji" => ["😀", 150.0],
      "a nonspacing mark (Mn)" => ["́", 0.0],
      "an enclosing mark (Me)" => ["⃝", 0.0],
      "a format character (Cf)" => ["‍", 0.0],
      "a control character (Cc)" => ["\u0007", 0.0],
    }.each do |name, (text, expected)|
      it "measures #{name} at its measured or estimated width" do
        expect(width(text)).to eq(expected)
      end
    end

    it "keeps a combining sequence at the width of its base" do
      expect(width("é")).to eq(width("e"))
    end

    it "never raises on text that is not valid UTF-8" do
      expect(undecodable.map { |text| width(text) }).to all(be > 0)
    end

    # Transcoding CESU-8 with invalid: :replace leaves a stray continuation
    # byte after U+FFFD that valid_encoding? accepts but String#ord rejects.
    it "never raises on a UTF-8 string that reports valid but cannot be read" do
      stray = (+"\xD7\xC2\xA8").force_encoding("CESU-8")
        .encode("UTF-8", invalid: :replace, undef: :replace)

      expect([stray.valid_encoding?, width(stray)])
        .to eq([true, width("\uFFFD\uFFFD")])
    end

    it "treats high bytes tagged as UTF-7 as replacement characters" do
      tagged = (+"a\xFFb").force_encoding("UTF-7")

      expect(width(tagged)).to eq(width("a\uFFFDb"))
    end

    it "measures every byte of ISO-8859-1 text as the character it is" do
      bytes = (0..255).map { |b| [b].pack("C").force_encoding("ISO-8859-1") }

      expect(bytes.map { |char| width(char) })
        .to eq(bytes.map { |char| width(char.encode("UTF-8")) })
    end

    it "honours a width override without touching the height" do
      expect(described_class.measure("Hi", font_size: 14, width: 50))
        .to eq(width: 50, height: 14.0)
    end

    it "honours a height override without touching the width" do
      expect(described_class.measure("Hi", font_size: 14, height: 9))
        .to eq(width: width("Hi", size: 14), height: 9)
    end
  end

  describe "monospace" do
    it "measures table characters and unknown ones at 0.6 em" do
      expect(width("Wi中", monospace: true)).to be_within(0.001).of(180.0)
    end

    it "measures an unknown codepoint at 0.6 em" do
      widths = %w[中 한].map { |char| width(char, monospace: true) }
      expect(widths).to eq([60.0, 60.0])
    end

    it "measures a tab at 0.6 em like any other monospace character" do
      expect(width("\t", monospace: true)).to eq(60.0)
    end

    it "leaves zero-width characters at zero" do
      zero = ["\u0301", "\u20DD", "\u200D", "\u0007", "\u0483"]

      expect(zero.map { |char| width(char, monospace: true) }).to all(eq(0.0))
    end
  end

  describe Sirena::TextMeasurement::ArialAdvances do
    # Keep this: nothing reads the order. It fails if a hand edit scrambles the
    # generator's sorted output, which a diff of a regenerated table would hide.
    it "lists codepoints in ascending order" do
      keys = described_class::TABLE.keys
      expect(keys).to eq(keys.sort)
    end

    it "gives every advance in DATA its own codepoint" do
      listed = described_class::DATA.gsub(/U\+\h+:/, "").split.length

      expect(described_class::TABLE.size).to eq(listed)
    end

    it "keeps every advance under three em" do
      expect(described_class::TABLE.values.max).to be < 3000
    end
  end
end
