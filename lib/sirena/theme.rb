# frozen_string_literal: true

require "lutaml/model"

module Sirena
  # Represents a complete visual theme for diagram rendering
  class Theme < Lutaml::Model::Serializable
  end
end

# Now load sub-models after Theme class is defined
require_relative "theme/color_palette"
require_relative "theme/typography"
require_relative "theme/shape_styles"
require_relative "theme/spacing_config"
require_relative "theme/effect_styles"

module Sirena
  class Theme
    attribute :name, :string
    attribute :description, :string
    attribute :colors, ColorPalette
    attribute :typography, Typography
    attribute :shapes, ShapeStyles
    attribute :spacing, SpacingConfig
    attribute :effects, EffectStyles

    yaml do
      map "name", to: :name
      map "description", to: :description
      map "colors", to: :colors
      map "typography", to: :typography
      map "shapes", to: :shapes
      map "spacing", to: :spacing
      map "effects", to: :effects
    end

    # Load theme from YAML file
    def self.load(path)
      yaml_content = File.read(path)
      from_yaml(yaml_content)
    end

    # Merge with another theme (for overrides)
    def merge(other_theme)
      merged = self.class.new(
        name: other_theme.name || name,
        description: other_theme.description || description,
        colors: merge_attribute(colors, other_theme.colors),
        typography: merge_attribute(typography, other_theme.typography),
        shapes: merge_attribute(shapes, other_theme.shapes),
        spacing: merge_attribute(spacing, other_theme.spacing),
        effects: merge_attribute(effects, other_theme.effects)
      )
      merged
    end

    private

    def merge_attribute(base, override)
      return base if override.nil?
      return override if base.nil?

      # For now, just use override if provided, base otherwise
      # Full deep merge would require iterating over attributes
      override
    end
  end
end