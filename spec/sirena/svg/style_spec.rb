# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Svg::Style do
  describe '#to_css' do
    # One row per attribute: the CSS property it must emit, and a value.
    {
      fill: ['fill', '#123456'],
      stroke: ['stroke', '#abcdef'],
      stroke_width: ['stroke-width', 3.5],
      stroke_dasharray: ['stroke-dasharray', '4 2'],
      opacity: ['opacity', 0.5],
      fill_opacity: ['fill-opacity', 0.25],
      stroke_opacity: ['stroke-opacity', 0.75],
      font_family: ['font-family', 'Courier'],
      font_size: ['font-size', 12.0],
      font_weight: ['font-weight', 'bold'],
      text_anchor: ['text-anchor', 'middle']
    }.each do |attribute, (css_name, value)|
      it "emits only #{css_name} when only #{attribute} is set" do
        style = described_class.new(attribute => value)

        expect(style.to_css).to eq("#{css_name}:#{value}")
      end
    end

    it 'is empty when nothing is set' do
      expect(described_class.new.to_css).to eq('')
    end

    it 'joins every set property with semicolons, in a fixed order' do
      style = described_class.new(
        text_anchor: 'end', fill: 'red', stroke_width: 1.5, stroke: 'blue'
      )

      expect(style.to_css).to eq(
        'fill:red;stroke:blue;stroke-width:1.5;text-anchor:end'
      )
    end

    it 'keeps a zero opacity, which is falsy in other languages but set here' do
      expect(described_class.new(opacity: 0.0).to_css).to eq('opacity:0.0')
    end
  end
end
