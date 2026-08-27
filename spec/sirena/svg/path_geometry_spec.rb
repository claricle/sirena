# frozen_string_literal: true

require 'spec_helper'

# Only the two ends matter, and only because an arrowhead has to sit on one
# of them pointing the right way. The cases here are the ones that decide
# where it lands: which point is last, and which point sets the heading.
RSpec.describe Sirena::Svg::PathGeometry do
  def terminus(data)
    described_class.new(data).terminus
  end

  def origin(data)
    described_class.new(data).origin
  end

  describe '#terminus' do
    it 'ends where the last line ends, heading along it' do
      anchor = terminus('M 0 0 L 10 0')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([10.0, 0.0, 1.0, 0.0])
    end

    it 'takes the heading from the last segment, not the first' do
      anchor = terminus('M 0 0 L 10 0 L 10 10')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([10.0, 10.0, 0.0, 1.0])
    end

    it 'keeps the last usable heading through a zero-length final line' do
      anchor = terminus('M 0 0 L 10 0 L 10 0')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([10.0, 0.0, 1.0, 0.0])
    end

    it 'has no terminus after a trailing bare move' do
      expect(terminus('M 0 0 L 10 0 M 50 50')).to be_nil
    end

    it 'uses a real segment after a move as the terminus' do
      anchor = terminus('M 0 0 L 10 0 M 50 50 L 60 50')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([60.0, 50.0, 1.0, 0.0])
    end

    it 'does not borrow the previous subpath heading after a move' do
      expect(terminus('M 0 0 L 10 0 M 50 50 L 50 50')).to be_nil
    end

    it 'finds a curve heading before a degenerate terminal control point' do
      anchor = terminus('M 0 0 C 0 0, 10 0, 10 0')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([10.0, 0.0, 1.0, 0.0])
    end

    # The one curve in the corpus. A Bezier leaves its end point along the
    # line from the second control point, so the chord would point wrong.
    it 'takes a curve heading from the control point next to the end' do
      anchor = terminus('M 0 0 C 0 10, 10 20, 20 20')

      expect([anchor.x, anchor.y]).to eq([20.0, 20.0])
      expect([anchor.dx.round(4), anchor.dy.round(4)]).to eq([1.0, 0.0])
    end

    it 'reflects a quadratic control point for smooth continuation' do
      anchor = terminus('M 0 0 Q 10 10 20 0 T 40 0')

      expect([anchor.x, anchor.y, anchor.dx.round(4), anchor.dy.round(4)])
        .to eq([40.0, 0.0, 0.7071, 0.7071])
    end

    it 'reflects relative quadratic controls in absolute space' do
      anchor = terminus('M 0 0 q 10 10 20 0 t 20 0')

      expect([anchor.x, anchor.y, anchor.dx.round(4), anchor.dy.round(4)])
        .to eq([40.0, 0.0, 0.7071, 0.7071])
    end

    it 'clears a quadratic control before later smooth curves' do
      anchor = terminus('M 0 0 Q 10 10 20 0 L 30 0 T 40 0 T 40 10')

      expect([anchor.x, anchor.y, anchor.dx.round(4), anchor.dy.round(4)])
        .to eq([40.0, 10.0, -0.7071, 0.7071])
    end

    it 'reflects a cubic control for a smooth outgoing tangent' do
      anchor = terminus('M 0 0 C 0 0, 10 0, 10 10 S 20 20, 20 20')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([20.0, 20.0, 1.0, 0.0])
    end

    it 'reflects relative cubic controls in absolute space' do
      anchor = terminus('M 0 0 c 0 0, 10 0, 10 10 s 10 10, 10 10')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([20.0, 20.0, 1.0, 0.0])
    end

    it 'follows a relative command from the current point' do
      anchor = terminus('M 5 5 l 10 0')

      expect([anchor.x, anchor.y]).to eq([15.0, 5.0])
    end

    it 'draws lines from the coordinates that follow a move' do
      anchor = terminus('M 0 0 10 0 10 10')

      expect([anchor.x, anchor.y, anchor.dy]).to eq([10.0, 10.0, 1.0])
    end

    it 'reads horizontal and vertical shorthand' do
      anchor = terminus('M 0 0 H 10 V 10')

      expect([anchor.x, anchor.y, anchor.dy]).to eq([10.0, 10.0, 1.0])
    end

    it 'closes back to the start of the subpath' do
      anchor = terminus('M 0 0 L 10 0 L 10 10 Z')

      expect([anchor.x, anchor.y]).to eq([0.0, 0.0])
    end

    it 'has no anchor when the path only moves' do
      expect(terminus('M 10 10')).to be_nil
    end

    it 'has no anchor when the last segment goes nowhere' do
      expect(terminus('M 10 10 L 10 10')).to be_nil
    end

    it 'has no anchor for data that is not a path' do
      expect(terminus('not a path')).to be_nil
    end

    it 'has no anchor for a command missing its arguments' do
      expect(terminus('M 0 0 L 10')).to be_nil
    end

    it 'keeps the last complete segment when the final command is short' do
      anchor = terminus('M 0 0 L 10 0 L 5')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([10.0, 0.0, 1.0, 0.0])
    end

    it 'has no anchor for empty data' do
      expect(terminus(nil)).to be_nil
    end

    # The chord of this half circle points along +x; the real end tangent
    # points along -y. Refusing beats pointing an arrowhead 90 degrees wrong.
    it 'has no anchor at the end of an arc' do
      expect(terminus('M 0 0 A 10 10 0 1 1 20 0')).to be_nil
    end

    # The arc must come second: a first arc has no prior terminus, so it
    # cannot prove that traversing the arc clears one already set.
    it 'has no anchor when the path ends on an arc after a line' do
      expect(terminus('M 0 0 L 10 0 A 5 5 0 0 1 20 10')).to be_nil
    end

    # The two flags are packed with no separator, which is valid SVG.
    it 'has no anchor when the path ends on a compact arc' do
      expect(terminus('M 0 0 L 10 0 a5 5 0 011 20 10')).to be_nil
    end

    it 'treats a zero horizontal radius arc as a straight line' do
      anchor = terminus('M 0 0 A 0 5 0 0 1 10 0')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([10.0, 0.0, 1.0, 0.0])
    end

    it 'treats a relative zero vertical radius arc as a straight line' do
      anchor = terminus('M 5 5 a 5 0 0 0 1 0 10')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([5.0, 15.0, 0.0, 1.0])
    end

    it 'still moves the pen through an arc, so the next segment is placed right' do
      anchor = terminus('M 0 0 A 5 5 0 0 1 10 0 l 5 0')

      expect([anchor.x, anchor.y, anchor.dx]).to eq([15.0, 0.0, 1.0])
    end

    it 'still moves the pen through a compact arc' do
      anchor = terminus('M 0 0 L 10 0 a5 5 0 01 20 10 l 5 0')

      expect([anchor.x, anchor.y, anchor.dx]).to eq([35.0, 10.0, 1.0])
    end

    # The endpoint cases below short-circuit before the finite-length guard,
    # so they cannot prove it rejects an infinite control-point delta.
    it 'has no anchor when a finite-ended curve has a non-finite control point' do
      expect(terminus('M 0 0 C 0 0, 1e400 0, 10 0')).to be_nil
    end

    it 'has no anchor when the heading is not finite' do
      expect(terminus('M 0 0 L 1e400 0')).to be_nil
    end

    it 'finds a unit heading for a finite segment at 1e308 scale' do
      anchor = terminus('M 0 0 L 1e308 0')

      expect([anchor.dx, anchor.dy]).to eq([1.0, 0.0])
    end

    it 'has no anchor when a non-finite endpoint follows a finite heading' do
      expect(terminus('M 0 0 L 5 0 L 1e400 0')).to be_nil
    end
  end

  describe '#origin' do
    it 'starts where the path starts, heading into the first segment' do
      anchor = origin('M 0 0 L 10 0 L 10 10')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([0.0, 0.0, 1.0, 0.0])
    end

    it 'takes a curve heading from the control point next to the start' do
      anchor = origin('M 0 0 C 0 10, 10 20, 20 20')

      expect([anchor.dx, anchor.dy]).to eq([0.0, 1.0])
    end

    it 'finds the first usable heading after a zero-length initial line' do
      anchor = origin('M 0 0 L 0 0 L 10 0')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([0.0, 0.0, 1.0, 0.0])
    end

    it 'keeps the first usable heading when later segments turn' do
      anchor = origin('M 0 0 L 0 0 L 10 0 L 10 10')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([0.0, 0.0, 1.0, 0.0])
    end

    it 'treats a zero-radius initial arc as a straight line' do
      anchor = origin('M 0 0 A 0 5 0 0 1 10 0')

      expect([anchor.x, anchor.y, anchor.dx, anchor.dy]).to eq([0.0, 0.0, 1.0, 0.0])
    end

    # The path begins on the arc, so the segment after it is not the start of
    # the path and must not be promoted to it.
    it 'has no anchor when an absolute arc comes first' do
      expect(origin('M 0 0 A 5 5 0 0 1 10 0 L 15 0')).to be_nil
    end

    it 'has no anchor when a relative arc comes first' do
      expect(origin('M 0 0 a 5 5 0 0 1 10 0 l 5 0')).to be_nil
    end

    it 'still starts at the path start when an arc comes later' do
      anchor = origin('M 0 0 L 10 0 A 5 5 0 0 1 20 0 L 30 0')

      expect([anchor.x, anchor.y]).to eq([0.0, 0.0])
    end
  end
end
