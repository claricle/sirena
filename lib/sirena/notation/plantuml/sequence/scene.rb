# frozen_string_literal: true

require "lutaml/model"
require_relative "../../../layout/scene"
require_relative "../scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Final-canvas geometry for a sequence diagram: coordinates and
        # drawable roles only; the renderer picks colours and strokes.
        class Scene < Sirena::Layout::Scene
          class Head < Lutaml::Model::Serializable
            attribute :id, :string
            attribute :kind, :string
            attribute :x, :float
            attribute :y, :float
            attribute :width, :float
            attribute :height, :float
            attribute :texts, PlantUML::Scene::Text, collection: true
          end

          # One shape at an arrow end: a "polygon" (points), a "line" or a
          # "circle". A polygon is filled with the edge colour when `filled`.
          class Mark < Lutaml::Model::Serializable
            attribute :kind, :string
            attribute :filled, :boolean
            attribute :heavy, :boolean
            attribute :points, :string
            attribute :x1, :float
            attribute :y1, :float
            attribute :x2, :float
            attribute :y2, :float
            attribute :cx, :float
            attribute :cy, :float
            attribute :r, :float
          end

          class Arrow < Lutaml::Model::Serializable
            attribute :id, :string
            attribute :path, :string
            attribute :dashed, :boolean
            attribute :marks, Mark, collection: true
            attribute :texts, PlantUML::Scene::Text, collection: true
          end

          class Frame < Lutaml::Model::Serializable
            attribute :x, :float
            attribute :y, :float
            attribute :width, :float
            attribute :height, :float
            attribute :texts, PlantUML::Scene::Text, collection: true
          end

          class Fragment < Lutaml::Model::Serializable
            attribute :x, :float
            attribute :y, :float
            attribute :width, :float
            attribute :height, :float
            attribute :tab_path, :string
            attribute :tab_fill, :string
            attribute :separators, PlantUML::Scene::Segment, collection: true
            attribute :texts, PlantUML::Scene::Text, collection: true
          end

          class Note < Lutaml::Model::Serializable
            attribute :path, :string
            attribute :fold_path, :string
            attribute :texts, PlantUML::Scene::Text, collection: true
          end

          # A warning PlantUML draws above the heads.
          class Banner < Lutaml::Model::Serializable
            attribute :x, :float
            attribute :y, :float
            attribute :width, :float
            attribute :height, :float
            attribute :texts, PlantUML::Scene::Text, collection: true
          end

          class Bar < Lutaml::Model::Serializable
            attribute :fill, :string
            attribute :x, :float
            attribute :y, :float
            attribute :width, :float
            attribute :height, :float
          end

          class Divider < Lutaml::Model::Serializable
            attribute :lines, PlantUML::Scene::Segment, collection: true
            attribute :x, :float
            attribute :y, :float
            attribute :width, :float
            attribute :height, :float
            attribute :texts, PlantUML::Scene::Text, collection: true
          end

          attribute :banners, Banner, collection: true
          attribute :frames, Frame, collection: true
          attribute :fragments, Fragment, collection: true
          attribute :notes, Note, collection: true
          attribute :dividers, Divider, collection: true
          attribute :bars, Bar, collection: true
          attribute :crosses, PlantUML::Scene::Segment, collection: true
          attribute :page_breaks, PlantUML::Scene::Segment, collection: true
          attribute :heads, Head, collection: true
          attribute :lifelines, PlantUML::Scene::Segment, collection: true
          attribute :arrows, Arrow, collection: true
        end
      end
    end
  end
end
