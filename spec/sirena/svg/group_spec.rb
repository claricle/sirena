# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Svg::Group do
  describe '#to_xml' do
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
