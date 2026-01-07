# frozen_string_literal: true

require "lutaml/model"

# Represents the color palette for diagram theming
class Sirena::Theme::ColorPalette < Lutaml::Model::Serializable
  attribute :background, :string
  attribute :surface, :string
  attribute :surface_variant, :string
  attribute :foreground, :string
  attribute :foreground_secondary, :string
  attribute :primary, :string
  attribute :secondary, :string
  attribute :accent, :string
  attribute :error, :string
  attribute :warning, :string
  attribute :success, :string
  attribute :info, :string
  attribute :node_fill, :string
  attribute :node_stroke, :string
  attribute :edge_stroke, :string
  attribute :label_text, :string
  attribute :hover_fill, :string
  attribute :active_fill, :string
  attribute :disabled_fill, :string

  yaml do
    map "background", to: :background
    map "surface", to: :surface
    map "surface_variant", to: :surface_variant
    map "foreground", to: :foreground
    map "foreground_secondary", to: :foreground_secondary
    map "primary", to: :primary
    map "secondary", to: :secondary
    map "accent", to: :accent
    map "error", to: :error
    map "warning", to: :warning
    map "success", to: :success
    map "info", to: :info
    map "node_fill", to: :node_fill
    map "node_stroke", to: :node_stroke
    map "edge_stroke", to: :edge_stroke
    map "label_text", to: :label_text
    map "hover_fill", to: :hover_fill
    map "active_fill", to: :active_fill
    map "disabled_fill", to: :disabled_fill
  end
end