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
          attribute :colour, :string
          attribute :size, :float
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
          attribute :fill, :string
          attribute :icon, :boolean
          attribute :texts, Text, collection: true
        end

        # An arrowhead or diamond (`points`), or the circled plus of a
        # nested class (`shape` "nesting", centred on `cx`, `cy`, its plus
        # sign the path `cross`).
        class Marker < Lutaml::Model::Serializable
          attribute :shape, :string
          attribute :points, :string
          attribute :filled, :boolean
          attribute :cx, :float
          attribute :cy, :float
          attribute :r, :float
          attribute :cross, :string
        end

        class Relation < Lutaml::Model::Serializable
          attribute :id, :string
          attribute :path, :string
          attribute :dashed, :boolean
          attribute :markers, Marker, collection: true
          attribute :texts, Text, collection: true
        end

        # A title, header, footer, caption or legend: a rectangle (drawn when
        # `fill` is set or `bordered`) holding one line of `content`.
        class Panel < Lutaml::Model::Serializable
          attribute :id, :string
          attribute :kind, :string
          attribute :x, :float
          attribute :y, :float
          attribute :width, :float
          attribute :height, :float
          attribute :fill, :string
          attribute :bordered, :boolean
          attribute :colour, :string
          attribute :font_size, :float
          attribute :bold, :boolean
          attribute :content, :string
        end

        # `panels` sit in canvas space. The rest of the scene is drawn
        # shifted by `content_x`, `content_y` inside the `background`.
        attribute :panels, Panel, collection: true
        attribute :background, :string
        attribute :content_x, :float
        attribute :content_y, :float
        attribute :frames, Frame, collection: true
        attribute :boxes, Box, collection: true
        attribute :relations, Relation, collection: true
      end
    end
  end
end
