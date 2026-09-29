# frozen_string_literal: true

require "lutaml/model"

# Represents typography settings for diagram theming
class Sirena::Theme::Typography < Lutaml::Model::Serializable
  attribute :font_family, :string
  attribute :font_family_monospace, :string
  attribute :font_size_small, :float
  attribute :font_size_normal, :float
  attribute :font_size_large, :float
  attribute :font_size_title, :float
  attribute :font_weight_normal, :string
  attribute :font_weight_bold, :string
  attribute :line_height, :float
  attribute :text_transform, :string

  yaml do
    map "font_family", to: :font_family
    map "font_family_monospace", to: :font_family_monospace
    map "font_size_small", to: :font_size_small
    map "font_size_normal", to: :font_size_normal
    map "font_size_large", to: :font_size_large
    map "font_size_title", to: :font_size_title
    map "font_weight_normal", to: :font_weight_normal
    map "font_weight_bold", to: :font_weight_bold
    map "line_height", to: :line_height
    map "text_transform", to: :text_transform
  end
end