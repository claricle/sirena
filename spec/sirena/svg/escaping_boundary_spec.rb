# frozen_string_literal: true

require 'spec_helper'

# The boundary, not a sample.
#
# Testing one hostile attribute per class is not enough — Path emits `d` and
# `marker-end` independently, and Document has five sites of its own, so a
# per-class test can pass while a site is missed. Grepping for raw
# interpolation is not enough either: it misses a subclass hook returning
# markup, and false-positives on legitimate coordinate builders.
#
# So the contract is the thing under test. `element_attributes` returns
# name/value pairs, never rendered markup, which leaves exactly one place an
# attribute becomes text.
HOSTILE = %(<&>"'x)
ESCAPED = '&lt;&amp;&gt;&quot;&apos;x'

# Every hook emits conditionally, so a default instance returns an empty
# array and the pair assertion would pass against raw-string code. Each
# class must be populated before it proves anything.
#
# Only the string-typed attributes are listed. The rest are declared
# :float, so lutaml coerces a hostile value to 0.0 and they cannot carry
# markup at all — asserting escaping on those would test the type system.
# They are still routed through the escaper; escaping a number is a no-op.
ELEMENT_ATTRIBUTES = {
  Sirena::Svg::Circle => [],
  Sirena::Svg::Line => [:stroke_dasharray],
  Sirena::Svg::Path => [:d, :stroke_dasharray, :stroke_linecap, :stroke_linejoin, :marker_end, :marker_start],
  Sirena::Svg::Polygon => [:points],
  Sirena::Svg::Rect => [:stroke_dasharray, :fill_opacity],
  Sirena::Svg::Text => [:text_anchor, :font_family, :font_size, :font_weight, :font_style, :dominant_baseline]
}.freeze

# Inherited from Element, so every subclass carries them.
COMMON_ATTRIBUTES = [:id, :class_name, :transform, :fill, :stroke,
                     :stroke_width, :stroke_opacity].freeze

RSpec.describe Sirena::Svg::Escaping do
  ELEMENT_ATTRIBUTES.each do |klass, writers|
    context klass.name.split('::').last do
      subject(:element) do
        klass.new.tap do |e|
          (writers + COMMON_ATTRIBUTES).each do |w|
            e.public_send("#{w}=", HOSTILE)
          end
        end
      end

      it 'returns pairs from element_attributes, never rendered markup' do
        pairs = element.send(:element_attributes)

        expect(pairs).to all(be_an(Array).and(have_attributes(size: 2)))
        expect(pairs.map(&:first)).to all(be_a(String))
      end

      it 'escapes every one of its string attribute values' do
        xml = element.to_xml
        # Rect declares fill-opacity in its own hook while Element already
        # emits it, so it appears twice. That duplicate is a real defect and
        # the last 5 malformed corpus cases — it has its own bucket, and this
        # counts it rather than hiding it.
        duplicates = klass == Sirena::Svg::Rect ? 1 : 0
        expected = writers.size + COMMON_ATTRIBUTES.size + duplicates

        expect(xml).not_to include(HOSTILE)
        expect(xml.scan(ESCAPED).size).to eq(expected)
      end
    end
  end

  # Document sits outside Element and serializes its own root tag, so the
  # contract above cannot reach it. Every root value is numeric or static in
  # production and the corpus has no special-character attribute case, so
  # misrouting Document alone would leave the rest of this suite green.
  describe Sirena::Svg::Document do
    it 'escapes its root attributes' do
      doc = described_class.new
      doc.view_box = HOSTILE
      doc.version = HOSTILE

      xml = doc.to_xml

      expect(xml).not_to include(HOSTILE)
      expect(xml).to include(%(viewBox="&lt;&amp;&gt;&quot;&apos;x"))
      expect(xml).to include(%(version="&lt;&amp;&gt;&quot;&apos;x"))
    end
  end

  # Text owns its opening tag AND carries content, which is the actual sink.
  describe Sirena::Svg::Text do
    it 'escapes its content' do
      text = described_class.new
      text.content = 'Alice<img src=x onerror=alert(1)>'

      expect(text.to_xml).not_to include('<img')
      expect(text.to_xml).to include('&lt;img')
    end
  end
end
