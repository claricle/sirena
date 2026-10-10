# frozen_string_literal: true

require "lutaml/model"
require_relative "../base"

module Sirena
  module Layout
    class Sequence < Base
      # A laid-out `box` group behind its participants.
      class BoxShape < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :color, :string
        attribute :title, :string
        attribute :title_y, :float
      end
    end
  end
end
