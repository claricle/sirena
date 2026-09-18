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
    end

    # Tspan is the one Element subclass that used to override the public
    # to_xml directly rather than the element_markup/xml_lines contract
    # every other subclass follows -- indented composition goes through
    # xml_lines/element_markup, so a Tspan reached only that way (as a
    # Group child, not via Text calling tspan.to_xml itself) silently
    # dropped its own content and emitted a bare self-closing tag.
    it "keeps a Tspan child's text content" do
      child = Sirena::Svg::Tspan.new(content: 'bold')
      group = described_class.new
      group << child

      expect(group.to_xml).to eq("<g>\n  <tspan>bold</tspan>\n</g>")
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
