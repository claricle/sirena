# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Svg::Group do
  describe '#to_xml' do
    it 'indents a Text child without changing newlines in its content' do
      child = Sirena::Svg::Text.new
      child.content = "This is a\nmultiline string\n"
      group = described_class.new
      group << child

      xml = group.to_xml

      expect(xml).to eq("<g>\n  <text>This is a\nmultiline string\n</text>\n</g>")
      expect(xml).to match(/^  <text\b/)
    end

    it 'indents every structural line of a nested Group' do
      child = described_class.new
      child << Sirena::Svg::Rect.new
      group = described_class.new
      group << child

      expect(group.to_xml).to eq("<g>\n  <g>\n    <rect/>\n  </g>\n</g>")
    end

    it 'indents every line of a multi-element child fragment' do
      child = Sirena::Svg::Path.new.tap do |path|
        path.d = 'M 0 0 L 10 0'
        path.stroke = '#000000'
        path.marker_end = 'url(#arrowhead)'
      end
      group = described_class.new
      group << child

      xml = group.to_xml

      expect(xml).to match(/^  <path\b/)
      expect(xml).to match(/^  <polygon\b/)
    end
  end
end
