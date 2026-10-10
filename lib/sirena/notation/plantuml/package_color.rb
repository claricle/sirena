# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # The fill written after a package name (`package p #yellow {`),
      # read as the hex colour PlantUML draws.
      module PackageColor
        extend self

        NAMED = {
          "blue" => "#0000FF", "gray" => "#808080", "green" => "#008000",
          "lightgray" => "#D3D3D3", "orange" => "#FFA500",
          "pink" => "#FFC0CB", "red" => "#FF0000", "white" => "#FFFFFF",
          "yellow" => "#FFFF00"
        }.freeze

        HEX = /\A\h{3}(?:\h{3})?\z/

        # @param text [String] the colour with its `#`
        # @return [String, nil] `#RRGGBB`, or nil for a name not listed
        def hex(text)
          digits = text.delete_prefix("#")
          return NAMED[digits.downcase] unless HEX.match?(digits)

          digits = digits.gsub(/\h/) { |digit| digit * 2 } if digits.size == 3
          "##{digits.upcase}"
        end
      end
    end
  end
end
