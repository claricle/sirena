# frozen_string_literal: true

require 'sirena/style_cascade/css_validity'

RSpec.describe Sirena::StyleCascade::CssValidity do
  describe '.valid?' do
    context 'with fill/stroke (color-valued properties)' do
      it 'accepts a 3-digit hex color' do
        expect(described_class.valid?('fill', '#f96')).to be true
      end

      it 'accepts a 4-digit hex color (with alpha)' do
        expect(described_class.valid?('fill', '#f96a')).to be true
      end

      it 'accepts a 6-digit hex color' do
        expect(described_class.valid?('stroke', '#ff9966')).to be true
      end

      it 'accepts an 8-digit hex color (with alpha)' do
        expect(described_class.valid?('stroke', '#ff996680')).to be true
      end

      it 'accepts an rgb() function' do
        expect(described_class.valid?('fill', 'rgb(255, 0, 0)')).to be true
      end

      it 'accepts an hsla() function' do
        expect(described_class.valid?('stroke', 'hsla(0, 100%, 50%, .5)')).to be true
      end

      it 'accepts a CSS Color Module 4 keyword' do
        expect(described_class.valid?('fill', 'cornflowerblue')).to be true
      end

      it 'accepts the "none" paint keyword' do
        expect(described_class.valid?('fill', 'none')).to be true
      end

      it 'accepts "currentcolor" (any case) as a valid color token' do
        expect(described_class.valid?('fill', 'currentColor')).to be true
      end

      it 'rejects a nonsense value' do
        expect(described_class.valid?('fill', 'bogus')).to be false
      end

      it 'rejects a value missing the leading hash on a hex-shaped string' do
        expect(described_class.valid?('stroke', 'ff9966')).to be false
      end
    end

    context 'with stroke-width (a length-valued property)' do
      it 'accepts a bare number' do
        expect(described_class.valid?('stroke-width', '2')).to be true
      end

      it 'accepts a number with a recognized unit' do
        expect(described_class.valid?('stroke-width', '1.5px')).to be true
      end

      it 'rejects a color keyword' do
        expect(described_class.valid?('stroke-width', 'red')).to be false
      end

      it 'rejects an empty string' do
        expect(described_class.valid?('stroke-width', '')).to be false
      end
    end

    context 'with a property this table has no opinion on' do
      it 'is always valid, so a caller never rejects an unmodeled property' do
        expect(described_class.valid?('font-family', 'anything at all')).to be true
      end
    end
  end
end
