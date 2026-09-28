# frozen_string_literal: true

require 'lutaml/model'

module Sirena
  module Layout
    # Base class for what a layout hands its renderer.
    #
    # A Scene holds final canvas coordinates: the renderer writes them out
    # verbatim and applies no origin. Subclasses live in the layout file
    # that produces them and declare attributes only; never add an `xml do`
    # block, because a Scene is never serialized.
    class Scene < Lutaml::Model::Serializable
      attribute :width, :float
      attribute :height, :float
    end
  end
end
