# frozen_string_literal: true

require "lutaml/model"

# Forward-declares Sirena::Theme so this file loads standalone (it defines
# Sirena::Theme::* compact-style). Matches the same forward declaration in
# theme.rb, which is why theme.rb can safely require this file back.
module Sirena
  class Theme < Lutaml::Model::Serializable
  end
end

# Represents spacing configuration for diagram theming
class Sirena::Theme::SpacingConfig < Lutaml::Model::Serializable # rubocop:disable Style/OneClassPerFile -- matches theme.rb's own forward declaration
  attribute :node_padding_x, :float
  attribute :node_padding_y, :float
  attribute :node_margin, :float
  attribute :edge_spacing, :float
  attribute :edge_label_offset, :float
  attribute :rank_spacing, :float
  attribute :node_spacing, :float

  yaml do
    map "node_padding_x", to: :node_padding_x
    map "node_padding_y", to: :node_padding_y
    map "node_margin", to: :node_margin
    map "edge_spacing", to: :edge_spacing
    map "edge_label_offset", to: :edge_label_offset
    map "rank_spacing", to: :rank_spacing
    map "node_spacing", to: :node_spacing
  end
end