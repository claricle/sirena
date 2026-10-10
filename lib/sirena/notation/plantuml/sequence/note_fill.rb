# frozen_string_literal: true

require_relative "fill"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The colour written after `note right`: a hex colour in the forms
        # {Fill} reads, or one of the names below, which PlantUML draws as
        # these hex values. Any other name is not read.
        module NoteFill
          extend self

          NAMES = {
            "red" => "#FF0000", "blue" => "#0000FF", "green" => "#008000",
            "yellow" => "#FFFF00", "orange" => "#FFA500",
            "pink" => "#FFC0CB", "lightblue" => "#ADD8E6",
            "lightgreen" => "#90EE90", "lightgray" => "#D3D3D3",
            "white" => "#FFFFFF", "black" => "#000000", "gray" => "#808080",
            "cyan" => "#00FFFF", "magenta" => "#FF00FF",
            "purple" => "#800080"
          }.freeze

          # @param token [String] such as `#red` or `#ff8800`
          # @return [Fill, nil] nil when the token is not one of the forms
          def read(token)
            hex = NAMES[token.to_s.delete_prefix("#").downcase]
            hex ? Fill.new(hex) : Fill.read(token)
          end
        end
      end
    end
  end
end
