# frozen_string_literal: true

require "lutaml/model"
require_relative "../../layout/scene"

module Sirena
  module Notation
    module PlantUML
      # Typed, final-canvas geometry handed from the PlantUML layout to its
      # renderer. The records contain coordinates and drawable roles only;
      # the renderer chooses colours, fonts and strokes from the theme.
      class Scene < Sirena::Layout::Scene
        class Text < Lutaml::Model::Serializable
          attribute :content, :string
          attribute :x, :float
          attribute :y, :float
          attribute :role, :string
          attribute :anchor, :string
        end

        class Segment < Lutaml::Model::Serializable
          attribute :x1, :float
          attribute :y1, :float
          attribute :x2, :float
          attribute :y2, :float
        end

        class Box < Lutaml::Model::Serializable
          attribute :id, :string
          attribute :x, :float
          attribute :y, :float
          attribute :width, :float
          attribute :height, :float
          attribute :texts, Text, collection: true
          attribute :separators, Segment, collection: true
          attribute :kind, :string
          attribute :fill, :string
        end

        class Frame < Lutaml::Model::Serializable
          attribute :id, :string
          attribute :x, :float
          attribute :y, :float
          attribute :width, :float
          attribute :height, :float
          attribute :tab_width, :float
          attribute :icon, :boolean
          attribute :texts, Text, collection: true
        end

        class Relation < Lutaml::Model::Serializable
          attribute :id, :string
          attribute :path, :string
          attribute :dashed, :boolean
          attribute :marker_points, :string
          attribute :marker_filled, :boolean
          attribute :texts, Text, collection: true
        end

        attribute :frames, Frame, collection: true
        attribute :boxes, Box, collection: true
        attribute :relations, Relation, collection: true
      end
    end
  end
end
