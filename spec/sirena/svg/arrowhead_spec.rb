# frozen_string_literal: true

require 'spec_helper'

# Every arrow Sirena drew before this pointed at nothing: four renderers set
# `marker-end="url(#arrowhead)"` and no document ever defined `#arrowhead`,
# so the head simply did not render. SVG Tiny 1.2 has no way to reference a
# marker at all, so the head is drawn as its own shape.
RSpec.describe Sirena::Svg::Arrowhead do
  def path(**attributes)
    Sirena::Svg::Path.new.tap do |p|
      attributes.each { |name, value| p.public_send("#{name}=", value) }
    end
  end

  def points_of(polygon)
    polygon.points.split.map { |pair| pair.split(',').map(&:to_f) }
  end

  describe '.for' do
    it 'draws nothing when the path asked for no marker' do
      expect(described_class.for(path(d: 'M 0 0 L 10 0'))).to be_empty
    end

    it 'puts the tip on the end of the path' do
      polygon = described_class.for(path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)')).first

      expect(points_of(polygon).first).to eq([10.0, 0.0])
    end

    it 'points the head along the last segment' do
      polygon = described_class.for(path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)')).first
      tip, left, right = points_of(polygon)

      # Both back corners sit one arrow-length behind the tip, on either side.
      expect(tip).to eq([10.0, 0.0])
      expect([left[0], right[0]]).to eq([6.0, 6.0])
      expect([left[1], right[1]]).to eq([2.0, -2.0])
    end

    it 'scales with the stroke width of the line it ends' do
      polygon = described_class.for(
        path(d: 'M 0 0 L 20 0', marker_end: 'url(#arrowhead)', stroke_width: '2')
      ).first

      expect(points_of(polygon)[1]).to eq([12.0, 4.0])
    end

    it 'takes the colour of the line, because it is part of it' do
      polygon = described_class.for(
        path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)', stroke: '#ff0000')
      ).first

      expect(polygon.fill).to eq('#ff0000')
    end

    it 'falls back to black, which is what a path with no stroke paints' do
      polygon = described_class.for(path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)')).first

      expect(polygon.fill).to eq('#000000')
    end

    # Without this the head lands in the untransformed coordinate space and
    # the line it belongs to lands somewhere else.
    it 'carries the transform of the path it ends' do
      polygon = described_class.for(
        path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)', transform: 'translate(5,5)')
      ).first

      expect(polygon.transform).to eq('translate(5,5)')
    end

    it 'points a start marker back the way the path came' do
      polygon = described_class.for(path(d: 'M 0 0 L 10 0', marker_start: 'url(#arrowhead)')).first
      tip, left = points_of(polygon)

      expect(tip).to eq([0.0, 0.0])
      expect(left).to eq([4.0, -2.0])
    end

    it 'draws both when the path asked for both' do
      arrows = described_class.for(
        path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)', marker_start: 'url(#arrowhead)')
      )

      expect(arrows.size).to eq(2)
    end

    # Drawing it in the wrong place is worse than not drawing it.
    it 'draws nothing when the path data gives no heading' do
      expect(described_class.for(path(d: 'M 10 10', marker_end: 'url(#arrowhead)'))).to be_empty
    end
  end
end
