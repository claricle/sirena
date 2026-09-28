# frozen_string_literal: true

require "lutaml/model"

# Forward-declares Sirena::Theme so this file loads standalone (it defines
# Sirena::Theme::* compact-style). Matches the same forward declaration in
# theme.rb, which is why theme.rb can safely require this file back.
module Sirena
  class Theme < Lutaml::Model::Serializable
  end
end

# Represents effect styles for diagram theming
class Sirena::Theme::EffectStyles < Lutaml::Model::Serializable # rubocop:disable Style/OneClassPerFile -- matches theme.rb's own forward declaration
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