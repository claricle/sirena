# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Layout
    # A positioned class-diagram note: the box, its text, and the line to
    # the class it belongs to. Coordinates are final canvas coordinates.
    class ClassNote < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :text, :string
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float

      # The id of the class the note hangs from; nil for a general note
      attribute :target_id, :string

      # Ends of the line to the class; nil for a general note
      attribute :link_x1, :float
      attribute :link_y1, :float
      attribute :link_x2, :float
      attribute :link_y2, :float

      def linked?
        !link_x1.nil?
      end
    end
  end
end
