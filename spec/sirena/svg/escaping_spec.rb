# frozen_string_literal: true

require 'spec_helper'

# Nothing Sirena wrote into an SVG was escaped. A diagram label reading
# `Alice<img src=` reached the document verbatim, which is both malformed XML
# and, since the output is embedded into Metanorma documents, a way for
# diagram source to become markup in someone else's document.
#
# These assert the exact escaped string rather than only that the result
# parses. Parsing is not enough: attributes are double-quoted, so a raw `>`
# or `'` stays well-formed and round-trips cleanly while still being wrong.
RSpec.describe Sirena::Svg::Escaping do
  describe '.escape_text' do
    {
      '&' => '&amp;',
      '<' => '&lt;',
      '>' => '&gt;'
    }.each do |raw, escaped|
      it "escapes #{raw.inspect} in text content" do
        expect(described_class.escape_text("a#{raw}b")).to eq("a#{escaped}b")
      end
    end

    it 'leaves quotes alone, which are legal in text' do
      expect(described_class.escape_text(%(a"b'c))).to eq(%(a"b'c))
    end

    it 'escapes an ampersand once, not twice' do
      expect(described_class.escape_text('&lt;')).to eq('&amp;lt;')
    end
  end

  describe '.escape_attribute' do
    {
      '&' => '&amp;',
      '<' => '&lt;',
      '>' => '&gt;',
      '"' => '&quot;',
      "'" => '&apos;'
    }.each do |raw, escaped|
      it "escapes #{raw.inspect} in an attribute value" do
        expect(described_class.escape_attribute("a#{raw}b"))
          .to eq("a#{escaped}b")
      end
    end
  end

  describe '.attributes' do
    it 'drops a nil value rather than emitting an empty attribute' do
      expect(described_class.attributes([%w[fill red], ['stroke', nil]]))
        .to eq(' fill="red"')
    end

    it 'keeps an empty string, which is a legal value' do
      expect(described_class.attributes([['fill', '']])).to eq(' fill=""')
    end
  end
end
