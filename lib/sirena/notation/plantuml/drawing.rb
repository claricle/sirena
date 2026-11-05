# frozen_string_literal: true

require_relative "drawing/box"
require_relative "drawing/face"
require_relative "drawing/scene"
require_relative "drawing/pen"
require_relative "drawing/renderer"

module Sirena
  module Notation
    module PlantUML
      # What the plain-picture families (network, timing, EBNF) share: a
      # scene of marks, a pen that lays marks down and a renderer that turns
      # them into SVG.
      module Drawing
      end
    end
  end
end
