# frozen_string_literal: true

require_relative "base"

module Sirena
  module Layout
    class UserJourney < Base
      # A point on the canvas.
      class FacePoint < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
      end

      # The mouth, in canvas coordinates: closed arc path data for a smile or
      # frown, or the two ends of a flat line for a neutral face.
      class FaceMouth < Lutaml::Model::Serializable
        attribute :path, :string
        attribute :line, Line
      end

      # A task's face and the column centre it hangs from, in canvas
      # coordinates.
      class Face < Lutaml::Model::Serializable
        attribute :center_x, :float
        attribute :center_y, :float
        attribute :radius, :float
        attribute :eyes, FacePoint, collection: true, default: -> { [] }
        attribute :mouth, FaceMouth
      end
    end
  end
end
