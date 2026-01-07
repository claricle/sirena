# frozen_string_literal: true

require "lutaml/model"

# Represents effect styles for diagram theming
class Sirena::Theme::EffectStyles < Lutaml::Model::Serializable
  attribute :shadow_enabled, :boolean
  attribute :shadow_color, :string
  attribute :shadow_blur, :float
  attribute :shadow_offset_x, :float
  attribute :shadow_offset_y, :float
  attribute :gradient_enabled, :boolean
  attribute :gradient_type, :string
  attribute :arrow_size, :float
  attribute :arrow_style, :string

  yaml do
    map "shadow_enabled", to: :shadow_enabled
    map "shadow_color", to: :shadow_color
    map "shadow_blur", to: :shadow_blur
    map "shadow_offset_x", to: :shadow_offset_x
    map "shadow_offset_y", to: :shadow_offset_y
    map "gradient_enabled", to: :gradient_enabled
    map "gradient_type", to: :gradient_type
    map "arrow_size", to: :arrow_size
    map "arrow_style", to: :arrow_style
  end
end