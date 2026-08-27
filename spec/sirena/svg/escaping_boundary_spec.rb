# frozen_string_literal: true

require 'spec_helper'

# The boundary, not a sample.
#
# Testing one hostile attribute per class is not enough — Path emits `d` and
# `stroke-dasharray` independently, and Document has six sites of its own, so a
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
  Sirena::Svg::Path => [:d, :stroke_dasharray, :stroke_linecap, :stroke_linejoin],
  Sirena::Svg::Polygon => [:points],
  Sirena::Svg::Polyline => [:points],
  Sirena::Svg::Ellipse => [],
  Sirena::Svg::Rect => [:stroke_dasharray],
  Sirena::Svg::Text => [:text_anchor, :font_family, :font_size, :font_weight, :font_style]
}.freeze

# Five renderers set marker-end, marker-start arrives only through from_xml,
# and renderers set dominant-baseline. None reaches the output — the SVG layer
# translates each into something SVG Tiny 1.2 has. They are not in the matrix
# above because there is no attribute left to escape; the cases further down
# assert they are gone.
TRANSLATED_AWAY = {
  Sirena::Svg::Path => {
    marker_end: [
      'marker-end',
      'url(#arrowhead)',
      [
        '<path stroke="#000000" d="M 0 0 L 10 0"/>',
        '<polygon fill="#000000" points="10.0,0.0 6.0,2.0 6.0,-2.0"/>'
      ]
    ],
    marker_start: [
      'marker-start',
      'url(#arrowhead)',
      [
        '<path stroke="#000000" d="M 0 0 L 10 0"/>',
        '<polygon fill="#000000" points="0.0,0.0 4.0,-2.0 4.0,2.0"/>'
      ]
    ]
  },
  Sirena::Svg::Text => {
    dominant_baseline: [
      'dominant-baseline',
      'middle',
      ['<text y="13.5" font-size="10"></text>']
    ]
  }
}.freeze

# What each class needs set before its translation can be seen: a Path draws
# no arrowhead without data and a stroke, and a Text shifts no baseline
# without a y and a font size. Held per class rather than chosen by asking the
# element what it responds to, so a third class added above fails loudly here
# instead of silently taking another class's setup.
TRANSLATED_AWAY_SETUP = {
  Sirena::Svg::Path => lambda { |path|
    path.d = 'M 0 0 L 10 0'
    path.stroke = '#000000'
  },
  Sirena::Svg::Text => lambda { |text|
    text.y = 10.0
    text.font_size = '10'
  }
}.freeze

# Inherited from Element, so every subclass carries them.
COMMON_ATTRIBUTES = [:id, :class_name, :transform, :fill, :fill_opacity,
                     :stroke, :stroke_width, :stroke_opacity].freeze

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
        # No duplicate allowance any more. Rect used to list fill-opacity in
        # writes_attributes while Element also emitted it, producing
        # `fill-opacity="x" fill-opacity="x"` and the last 5 malformed corpus
        # cases. Every class now emits each attribute exactly once.
        expected = writers.size + COMMON_ATTRIBUTES.size

        expect(xml).not_to include(HOSTILE)
        expect(xml.scan(ESCAPED).size).to eq(expected)
      end
    end
  end

  # Four of the six properties the profile has no room for: `opacity`,
  # `marker-end`, `marker-start` and `dominant-baseline`. The `dx` and `dy`
  # translations are covered in tiny_properties_spec.
  describe 'properties SVG Tiny 1.2 does not have' do
    TRANSLATED_AWAY.each do |klass, writers|
      writers.each do |writer, (attribute, sample, expected_lines)|
        it "never emits #{attribute} from #{klass.name.split('::').last}" do
          element = klass.new
          TRANSLATED_AWAY_SETUP.fetch(klass).call(element)
          element.public_send("#{writer}=", sample)

          xml = element.to_xml

          expect(xml).not_to include(attribute)
          expect(xml.lines(chomp: true)).to eq(expected_lines)
        end
      end
    end

    it 'never emits opacity, which Tiny replaces with the two components' do
      rect = Sirena::Svg::Rect.new
      rect.opacity = 0.3

      expect(rect.to_xml).to eq('<rect fill-opacity="0.3" stroke-opacity="0.3"/>')
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
      doc.base_profile = HOSTILE
      doc.xmlns = HOSTILE

      xml = doc.to_xml

      # All four string-typed root attributes, not a sample: each is emitted
      # on its own line, so asserting three of four would miss a dropped one.
      # width and height are :float and coerce to 0.0, so they cannot carry
      # markup — same as the numeric element attributes.
      expect(xml).not_to include(HOSTILE)
      %w[viewBox version baseProfile xmlns].each do |name|
        expect(xml).to include(%(#{name}="#{ESCAPED}"))
      end
    end

    it 'declares and round-trips the SVG Tiny 1.2 profile' do
      defaults = described_class.new.to_xml
      xml = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" version="1.1" baseProfile="full"/>
      SVG
      parsed = described_class.from_xml(xml)

      expect(defaults).to include(%( version="1.2"\n baseProfile="tiny"))
      expect(parsed.version).to eq('1.1')
      expect(parsed.base_profile).to eq('full')
      expect(parsed.to_xml).to include(%( version="1.1"\n baseProfile="full"))
    end
  end

  # Group owns its opening tag too, and carries user data — the C4 renderer
  # assigns edge ids straight onto it. A seeded raw interpolation here left the
  # entire suite green, so it needs its own case.
  describe Sirena::Svg::Group do
    it 'escapes the attributes on its opening tag' do
      group = described_class.new
      group.id = HOSTILE
      group.class_name = HOSTILE
      group.transform = HOSTILE

      xml = group.to_xml

      expect(xml).not_to include(HOSTILE)
      expect(xml.scan(ESCAPED).size).to eq(3)
    end
  end

  # Text owns its opening tag AND carries content, which is the actual sink.
  describe Sirena::Svg::Text do
    # Checking only for `<img` let a `<`-only escaper pass while leaving raw
    # `&` and `>` in the output. Assert the exact string instead.
    it 'escapes every special character in its content' do
      text = described_class.new
      text.content = '& < >'

      expect(text.to_xml).to eq('<text>&amp; &lt; &gt;</text>')
    end

    it 'neutralises a script payload' do
      text = described_class.new
      text.content = 'Alice<img src=x onerror=alert(1)>'

      expect(text.to_xml).to include('&lt;img src=x onerror=alert(1)&gt;')
      expect(text.to_xml).not_to include('<img')
    end

    # lutaml leaves unset attributes holding a sentinel that returns itself
    # from to_s and gsub, so it escaped to a raw `#<...>` and broke the XML.
    it 'omits attributes lutaml left uninitialised' do
      xml = described_class.from_xml('<text>x</text>').to_xml

      expect(xml).to eq('<text>x</text>')
      expect(xml).not_to include('Uninitialized')
    end
  end

  # Both emitted NO geometry before this change — `<ellipse fill="red"/>` with
  # no cx/cy/rx/ry — while renderer/c4.rb:242 and renderer/xy_chart.rb:337 draw
  # with them. Their attributes are numeric or a coordinate string, so the
  # escaping matrix above cannot cover them; these assert the exact output, and
  # removing either declaration fails here.
  describe 'geometry that used to be dropped' do
    it 'serialises an Ellipse with all four of its radii and centres' do
      ellipse = Sirena::Svg::Ellipse.new
      ellipse.cx = 10.0
      ellipse.cy = 20.0
      ellipse.rx = 5.0
      ellipse.ry = 6.0

      expect(ellipse.to_xml)
        .to eq('<ellipse cx="10.0" cy="20.0" rx="5.0" ry="6.0"/>')
    end

    it 'serialises a Polyline with its points' do
      polyline = Sirena::Svg::Polyline.new
      polyline.points = '1,2 3,4'

      expect(polyline.to_xml).to eq('<polyline points="1,2 3,4"/>')
    end
  end

  # XML 1.0 has no escape for most C0 controls, and a sequence label accepts
  # any non-line-ending character, so a NUL reached the document and made it
  # unparseable.
  describe 'characters XML cannot represent' do
    it 'drops a forbidden control from text' do
      expect(described_class.escape_text("a\u0000b\u000Bc")).to eq('abc')
    end

    it 'keeps tab, newline and carriage return, which are legal' do
      expect(described_class.escape_text("a\tb\nc\rd")).to eq("a\tb\nc\rd")
    end
  end

  describe 'the pair contract' do
    it 'refuses a pre-rendered string instead of dropping it' do
      expect { described_class.attributes([%( x="1")]) }
        .to raise_error(ArgumentError, /pair/)
    end

    # Only values were escaped, so a name carrying a quote injected a second
    # attribute and the document stayed valid.
    it 'refuses an attribute name that would inject another attribute' do
      expect { described_class.attributes([[%(x="s" onload), 'boom']]) }
        .to raise_error(ArgumentError, /attribute name/)
    end
  end
end
