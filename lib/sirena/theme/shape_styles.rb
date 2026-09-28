# frozen_string_literal: true

require "lutaml/model"

# Forward-declares Sirena::Theme so this file loads standalone (it defines
# Sirena::Theme::* compact-style). Matches the same forward declaration in
# theme.rb, which is why theme.rb can safely require this file back.
module Sirena
  class Theme < Lutaml::Model::Serializable
  end
end

# Represents shape styling settings for diagram theming
class Sirena::Theme::ShapeStyles < Lutaml::Model::Serializable # rubocop:disable Style/OneClassPerFile -- matches theme.rb's own forward declaration
  attribute :stroke_width, :float
  attribute :stroke_width_thick, :float
  attribute :stroke_width_thin, :float
  attribute :fill_opacity, :float
  attribute :stroke_opacity, :float
  attribute :corner_radius, :float
  attribute :corner_radius_large, :float
  attribute :dash_pattern_dotted, :string
  attribute :dash_pattern_dashed, :string

  yaml do
    map "stroke_width", to: :stroke_width
    map "stroke_width_thick", to: :stroke_width_thick
    map "stroke_width_thin", to: :stroke_width_thin
    map "fill_opacity", to: :fill_opacity
    map "stroke_opacity", to: :stroke_opacity
    map "corner_radius", to: :corner_radius
    map "corner_radius_large", to: :corner_radius_large
    map "dash_pattern_dotted", to: :dash_pattern_dotted
    map "dash_pattern_dashed", to: :dash_pattern_dashed
  end
end