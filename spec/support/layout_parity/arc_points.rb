# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Points along an SVG elliptical arc. SVG 1.1 appendix F.6.5: endpoint to
    # center parameterization, then the ellipse sampled by sweep fraction.
    class ArcPoints
      FULL_TURN = 2 * Math::PI

      # flags is [large_arc, sweep], both booleans.
      def initialize(start:, target:, radii:, rotation:, flags:)
        @start = start
        @target = target
        @large, @sweep = flags
        orient(rotation)
        @half = half_difference
        @radii = fit(radii)
        derive_sweep
      end

      # The point at `fraction` (0..1) of the sweep.
      def at(fraction)
        angle = @theta + (@delta * fraction)
        cos_a = Math.cos(angle)
        sin_a = Math.sin(angle)
        [point_x(cos_a, sin_a), point_y(cos_a, sin_a)]
      end

      private

      def orient(rotation)
        phi = rotation * Math::PI / 180
        @cos = Math.cos(phi)
        @sin = Math.sin(phi)
      end

      def derive_sweep
        @offset = center_offset
        @center = center
        @theta = start_angle
        @delta = sweep_angle
      end

      def rx
        @radii[0]
      end

      def ry
        @radii[1]
      end

      def point_x(cos_a, sin_a)
        @center[0] + (@cos * rx * cos_a) - (@sin * ry * sin_a)
      end

      def point_y(cos_a, sin_a)
        @center[1] + (@sin * rx * cos_a) + (@cos * ry * sin_a)
      end

      # The start point rotated into the ellipse's frame, halved.
      def half_difference
        dx = half_gap(0)
        dy = half_gap(1)
        [(@cos * dx) + (@sin * dy), (-@sin * dx) + (@cos * dy)]
      end

      def half_gap(axis)
        (@start[axis] - @target[axis]) / 2
      end

      def midpoint(axis)
        (@start[axis] + @target[axis]) / 2
      end

      # Radii too small to span the endpoints are scaled up to fit.
      def fit(radii)
        x1, y1 = @half
        lam = ((x1**2) / (radii[0]**2)) + ((y1**2) / (radii[1]**2))
        return radii unless lam > 1

        radii.map { |radius| radius * Math.sqrt(lam) }
      end

      def center_offset
        x1, y1 = @half
        coef = center_coefficient
        [coef * rx * y1 / ry, -coef * ry * x1 / rx]
      end

      def center_coefficient
        sign = @large == @sweep ? -1 : 1
        Math.sqrt([numerator / denominator, 0].max) * sign
      end

      def numerator
        x1, y1 = @half
        rx2, ry2 = @radii.map { |radius| radius**2 }
        (rx2 * ry2) - (rx2 * (y1**2)) - (ry2 * (x1**2))
      end

      def denominator
        x1, y1 = @half
        rx2, ry2 = @radii.map { |radius| radius**2 }
        (rx2 * (y1**2)) + (ry2 * (x1**2))
      end

      def center
        [(@cos * @offset[0]) - (@sin * @offset[1]) + midpoint(0),
         (@sin * @offset[0]) + (@cos * @offset[1]) + midpoint(1)]
      end

      def start_angle
        x1, y1 = @half
        Math.atan2((y1 - @offset[1]) / ry, (x1 - @offset[0]) / rx)
      end

      def end_angle
        x1, y1 = @half
        Math.atan2((-y1 - @offset[1]) / ry, (-x1 - @offset[0]) / rx)
      end

      def sweep_angle
        delta = end_angle - @theta
        return delta + FULL_TURN if @sweep && delta.negative?
        return delta - FULL_TURN if !@sweep && delta.positive?

        delta
      end
    end
  end
end
