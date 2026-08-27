# frozen_string_literal: true

require 'spec_helper'

# The two properties that are translated rather than dropped. SVG Tiny 1.2
# has neither `opacity` nor `dominant-baseline`, but both carry intent a
# renderer needs, so the intent is expressed in something Tiny does have.
#
# At the boundary, on bare elements: a renderer inherits this by
# construction, and a new one gets it without opting in.
RSpec.describe Sirena::Svg do
  describe 'opacity, which Tiny splits into fill and stroke' do
    def rect(**attributes)
      Sirena::Svg::Rect.new.tap do |r|
        attributes.each { |name, value| r.public_send("#{name}=", value) }
      end
    end

    it 'paints both components at the whole-element fraction' do
      expect(rect(opacity: 0.3).to_xml)
        .to eq('<rect fill-opacity="0.3" stroke-opacity="0.3"/>')
    end

    it 'multiplies through a fill-opacity the renderer already set' do
      expect(rect(opacity: 0.5, fill_opacity: '0.8').to_xml)
        .to eq('<rect fill-opacity="0.4" stroke-opacity="0.5"/>')
    end

    it 'clamps negative whole and component opacities before multiplying' do
      expect(rect(opacity: -1, fill_opacity: '-1').to_xml)
        .to eq('<rect fill-opacity="0.0" stroke-opacity="0.0"/>')
    end

    it 'clamps opacities above one before multiplying' do
      expect(rect(opacity: 2, fill_opacity: '0.5').to_xml)
        .to eq('<rect fill-opacity="0.5" stroke-opacity="1.0"/>')
    end

    it 'leaves the components alone when there is no whole-element opacity' do
      expect(rect(fill_opacity: '0.3').to_xml).to eq('<rect fill-opacity="0.3"/>')
    end

    # Nothing in the gem writes one, but the attribute is public. Inventing a
    # factor for a keyword would emit a number nobody asked for.
    it 'leaves a component it cannot multiply exactly as it was' do
      expect(rect(opacity: 0.5, fill_opacity: 'inherit').to_xml)
        .to eq('<rect fill-opacity="inherit" stroke-opacity="0.5"/>')
    end

    # A non-finite operand is left alone because Float::NAN cannot be clamped;
    # a caller-supplied error value must not make the whole document fail.
    it 'does not raise for a non-finite opacity' do
      expect(rect(opacity: Float::NAN).to_xml).to eq('<rect/>')
    end
  end

  def text(**attributes)
    Sirena::Svg::Text.new.tap do |t|
      attributes.each { |name, value| t.public_send("#{name}=", value) }
    end
  end

  describe 'dominant-baseline, which Tiny expresses by moving the baseline' do
    it 'drops a centred label half an x-height below its anchor' do
      expect(text(y: 67.0, font_size: '14', dominant_baseline: 'middle').to_xml)
        .to eq('<text y="71.9" font-size="14"></text>')
    end

    # The lookup normalises before it matches, the same way the arrowhead's
    # marker predicate does. Without that, a value SVG accepts falls through
    # to no shift at all and the label silently stays put.
    ['MIDDLE', ' middle ', 'Middle'].each do |value|
      it "reads #{value.inspect} as the centred baseline it is" do
        expect(text(y: 67.0, font_size: '14', dominant_baseline: value).to_xml)
          .to eq('<text y="71.9" font-size="14"></text>')
      end
    end

    it 'drops a central label half an x-height below its anchor' do
      expect(text(y: 10.0, font_size: '10', dominant_baseline: 'central').to_xml)
        .to include('y="13.5"')
    end

    it 'hangs a label a full ascender below its anchor' do
      expect(text(y: 10.0, font_size: '10', dominant_baseline: 'hanging').to_xml)
        .to include('y="18.0"')
    end

    it 'hangs a text-before-edge label a full ascender below its anchor' do
      expect(text(y: 10.0, font_size: '10', dominant_baseline: 'text-before-edge').to_xml)
        .to include('y="18.0"')
    end

    it 'lifts a bottom-aligned label by a descender' do
      expect(text(y: 10.0, font_size: '10', dominant_baseline: 'text-after-edge').to_xml)
        .to include('y="8.0"')
    end

    it 'lifts an ideographic label by a descender' do
      expect(text(y: 10.0, font_size: '10', dominant_baseline: 'ideographic').to_xml)
        .to include('y="8.0"')
    end

    it 'leaves the baseline where it was for a value that means baseline' do
      expect(text(y: 10.0, font_size: '10', dominant_baseline: 'auto').to_xml)
        .to include('y="10.0"')
    end

    it 'leaves the baseline where it was for a value it does not know' do
      expect(text(y: 10.0, font_size: '10', dominant_baseline: 'nonsense').to_xml)
        .to include('y="10.0"')
    end

    it 'scales the shift with the font size, not by a fixed amount' do
      expect(text(y: 0.0, font_size: '40', dominant_baseline: 'middle').to_xml)
        .to include('y="14.0"')
    end

    it 'falls back to the CSS initial size when the label carries none' do
      expect(text(y: 0.0, dominant_baseline: 'middle').to_xml).to include('y="5.6"')
    end

    it 'leaves y alone entirely when no baseline was asked for' do
      expect(text(y: 10.0).to_xml).to eq('<text y="10.0"></text>')
    end
  end
end
