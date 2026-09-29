# frozen_string_literal: true

require "lutaml/model"

module Sirena
  # Forward declaration so each theme sub-model file (color_palette.rb,
  # typography.rb, shape_styles.rb, spacing_config.rb, effect_styles.rb) can
  # load standalone, since each defines Sirena::Theme::* compact-style and
  # needs Sirena::Theme to exist first. theme.rb requires this file before
  # requiring those sub-models back, then reopens `Theme` to add its real
  # attributes -- which is safe because this declaration is idempotent.
  class Theme < Lutaml::Model::Serializable
  end
end
