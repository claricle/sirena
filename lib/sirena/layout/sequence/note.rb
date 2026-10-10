# frozen_string_literal: true

module Sirena
  module Layout
    class Sequence < Base
      # A positioned note: its box and one label per text line.
      class Note < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :lines, Label, collection: true, default: -> { [] }
      end
    end
  end
end
