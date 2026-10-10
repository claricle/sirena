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
      end
    end
  end
end
