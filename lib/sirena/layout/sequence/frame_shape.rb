# frozen_string_literal: true

require "lutaml/model"
require_relative "frame_divider"

module Sirena
  module Layout
    class Sequence < Base
      # A laid-out control block: its outline, label tab and dividers.
      class FrameShape < Lutaml::Model::Serializable
        attribute :kind, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float

        # Colour of a `rect`; nil for the other kinds
        attribute :color, :string

        # Width of the keyword tab; zero for a `rect`
        attribute :tab_width, :float

        # The bracketed title, nil when the block has none
        attribute :title, :string
        attribute :dividers, FrameDivider, collection: true,
                                           default: -> { [] }
      end
    end
  end
end
