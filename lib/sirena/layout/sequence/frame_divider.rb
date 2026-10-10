# frozen_string_literal: true

require "lutaml/model"
require_relative "../base"

module Sirena
  module Layout
    class Sequence < Base
      # The dashed line that starts an `else`, `and` or `option` section.
      class FrameDivider < Lutaml::Model::Serializable
        attribute :y, :float
        attribute :text, :string
        attribute :text_y, :float

        # Left and right ends of the line, and the text's centre
        attribute :x1, :float
        attribute :x2, :float
        attribute :text_x, :float
      end
    end
  end
end
