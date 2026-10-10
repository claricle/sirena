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
      attribute :font_size, :float
    end
  end
end
