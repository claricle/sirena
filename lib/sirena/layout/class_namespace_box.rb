# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Layout
    # A positioned namespace box: the rectangle drawn around its classes
    # and the title centred along its top edge, in final canvas
    # coordinates.
    class ClassNamespaceBox < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :title, :string
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float
    end
  end
end
