# frozen_string_literal: true

require_relative 'svg/escaping'
require_relative 'svg/numbers'
require_relative 'svg/path_geometry'
require_relative 'svg/style'
require_relative 'svg/element'
require_relative 'svg/document'
require_relative 'svg/group'
require_relative 'svg/rect'
require_relative 'svg/circle'
require_relative 'svg/line'
require_relative 'svg/polygon'
require_relative 'svg/arrowhead'
require_relative 'svg/path'
require_relative 'svg/polyline'
require_relative 'svg/tspan'
require_relative 'svg/text'
require_relative 'svg/ellipse'

module Sirena
  # The SVG document model. Everything Sirena writes into an SVG goes
  # through these classes.
  module Svg
    # The svg_conform profile Sirena's output is built to satisfy.
    #
    # Requires a viewBox, rejects @import/<link>/external images, and
    # enforces the SVG Tiny 1.2 element/attribute table -- but does not
    # by itself guarantee self-containment: an external
    # <?xml-stylesheet?> PI still validates clean under it. Nothing
    # Sirena emits produces one; spec/svg_conformance_spec.rb holds
    # that line -- don't drop it assuming the profile alone covers it.
    #
    # :svg_1_2_rfc restricts colour/fonts and would erase themes -- not
    # a drop-in equivalent.
    CONFORMANCE_PROFILE = :metanorma
  end
end
