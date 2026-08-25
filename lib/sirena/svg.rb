# frozen_string_literal: true

require_relative 'svg/escaping'
require_relative 'svg/numbers'
require_relative 'svg/path_geometry'
require_relative 'svg/arrowhead'
require_relative 'svg/style'
require_relative 'svg/element'
require_relative 'svg/document'
require_relative 'svg/group'
require_relative 'svg/rect'
require_relative 'svg/circle'
require_relative 'svg/path'
require_relative 'svg/line'
require_relative 'svg/polygon'
require_relative 'svg/polyline'
require_relative 'svg/text'
require_relative 'svg/ellipse'

module Sirena
  # The SVG document model. Everything Sirena writes into an SVG goes
  # through these classes.
  module Svg
    # The svg_conform profile Sirena's output is built to satisfy.
    #
    # Sirena's SVG is embedded straight into Metanorma documents, and this
    # is the profile Metanorma asks for. It requires the SVG namespace and a
    # viewBox, forbids external CSS, fonts and images, and enforces the SVG
    # Tiny 1.2 element and attribute table — while leaving colours, fonts
    # and styles free.
    #
    # The alternatives do not fit. `:svg_1_2_rfc` restricts colour to black
    # and white and fonts to the three generic families, which would erase
    # the themes for no benefit outside IETF publication. `:base` and
    # `:no_external_css` check so little that passing them would say
    # nothing. `:lucid_fix` is for cleaning up LucidChart exports.
    #
    # Named here because the profile is a decision about what Sirena emits,
    # not a detail of how it is tested. Three properties are missing from
    # the output because of it — see Svg::Arrowhead, Svg::Text and
    # Svg::Element.
    CONFORMANCE_PROFILE = :metanorma
  end
end
