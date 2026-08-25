# frozen_string_literal: true

require 'spec_helper'

# Every arrow Sirena drew before this pointed at nothing: the five renderers
# that ask for a head set `marker-end="url(#arrowhead)"` and no document ever
# defined `#arrowhead`, so the head simply did not render. SVG Tiny 1.2 has no way to reference a
# marker at all, so the head is drawn as its own shape.
RSpec.describe Sirena::Svg::Arrowhead do
  # A stroke by default, because an unstroked path paints no line and so
  # gets no head — the cases below are about geometry, not about that.
  def path(**attributes)
    Sirena::Svg::Path.new.tap do |p|
      p.stroke = '#000000'
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

    # An arrowhead is the end of a line. A path with no stroke paints no
    # line — SVG's initial `stroke` is `none` — so a head there would be a
    # black triangle floating on its own. Reachable: a partial theme leaves
    # edge_stroke unset and apply_theme_to_edge then sets no stroke.
    # nil covers a stroke nobody ever set as well: lutaml holds nil for an
    # unset Path stroke, whether it was built in Ruby or parsed in.
    ['none', 'NONE', '', nil].each do |value|
      it "draws nothing for a path whose stroke is #{value.inspect}" do
        unstroked = path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)')
        unstroked.stroke = value

        expect(described_class.for(unstroked)).to be_empty
      end
    end

    it 'paints the head at the stroke opacity of the line it ends' do
      polygon = described_class.for(
        path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)', stroke_opacity: '0.5')
      ).first

      expect(polygon.fill_opacity).to eq('0.5')
    end

    it 'carries the whole-element opacity of the path it ends' do
      polygon = described_class.for(
        path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)', opacity: 0.4)
      ).first

      expect(polygon.opacity).to eq(0.4)
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

    # `none` is SVG's own way of saying no marker here, so a path carrying it
    # has asked for nothing rather than failed to ask.
    ['none', 'NONE', '  none  '].each do |value|
      it "draws nothing for a marker of #{value.inspect}" do
        expect(described_class.for(path(d: 'M 0 0 L 10 0', marker_end: value))).to be_empty
      end
    end

    it 'draws nothing for an empty marker value' do
      expect(described_class.for(path(d: 'M 0 0 L 10 0', marker_end: ''))).to be_empty
    end

    # An arc's chord is not its tangent — on this half circle they are 90
    # degrees apart — and there is no control point to read one from.
    it 'draws nothing at the end of an arc rather than pointing along its chord' do
      arrows = described_class.for(path(d: 'M 0 0 A 10 10 0 1 1 20 0', marker_end: 'url(#arrowhead)'))

      expect(arrows).to be_empty
    end

    # The arc still moves the pen, so a segment after it starts in the right
    # place and can carry the head.
    it 'still ends where a segment after an arc ends' do
      polygon = described_class.for(
        path(d: 'M 0 0 A 5 5 0 0 1 10 0 L 20 0', marker_end: 'url(#arrowhead)')
      ).first

      expect(points_of(polygon).first).to eq([20.0, 0.0])
    end

    # Infinity/Infinity is NaN, and NaN would be written into points verbatim.
    it 'draws nothing when the path data has no finite heading' do
      arrows = described_class.for(path(d: 'M 0 0 L 1e400 0', marker_end: 'url(#arrowhead)'))

      expect(arrows).to be_empty
    end

    # The early return is what keeps a marker-less path from paying for a
    # scan of its own data, and most paths carry no marker.
    it 'does not read the path data when no marker was asked for' do
      allow(Sirena::Svg::PathGeometry).to receive(:new)

      described_class.for(path(d: 'M 0 0 L 10 0'))

      expect(Sirena::Svg::PathGeometry).not_to have_received(:new)
    end

    # SVG's initial stroke-width is 1, so a line whose width cannot be read
    # still paints one and still ends in a head. `1e400` is in this group for
    # a second reason: it reads as Infinity, and 0.0 * Infinity is NaN, which
    # would otherwise be written into the points verbatim.
    ['1e400', 'inherit'].each do |width|
      it "falls back to a 1-unit line for a stroke width of #{width.inspect}" do
        odd = path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)',
                   stroke_width: width)

        points = described_class.for(odd).first.points

        expect(points).to eq('10.0,0.0 6.0,2.0 6.0,-2.0')
      end
    end

    # A width SVG can read is a different matter: `stroke-width="0"` paints no
    # stroke at all, so substituting 1 would put a head on an invisible line —
    # the free-floating triangle this class exists to avoid. Reachable from a
    # custom theme carrying `stroke_width: 0`.
    ['0', '0.0', '-2'].each do |width|
      it "draws nothing for a line of stroke width #{width.inspect}" do
        unpainted = path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)',
                         stroke_width: width)

        expect(described_class.for(unpainted)).to be_empty
      end
    end

    # A Path is mutable, so nothing may remember an answer for data the
    # caller has since replaced.
    it 'reads the path data again when it has changed underneath' do
      moving = path(d: 'M 0 0 L 10 0', marker_end: 'url(#arrowhead)')
      arrowhead = described_class.new(moving)

      first = arrowhead.polygons.first.points
      moving.d = 'M 0 0 L 20 0'

      expect(arrowhead.polygons.first.points).not_to eq(first)
    end
  end
end
