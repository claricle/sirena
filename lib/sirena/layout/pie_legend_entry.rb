# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Layout
    # One legend row of a pie chart: a colour swatch and its caption.
    class PieLegendEntry < Lutaml::Model::Serializable
      attribute :text, :string
      attribute :color_index, :integer
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float
      attribute :font_size, :float
      # Where the caption is anchored, so the renderer only reads it.
      attribute :text_x, :float
      attribute :text_y, :float
    end
  end
end
