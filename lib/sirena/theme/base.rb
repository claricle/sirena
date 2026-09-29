# frozen_string_literal: true

require "lutaml/model"

module Sirena
  # Reopens Theme only to nest Base under it (Theme's own attributes stay
  # defined once, in theme.rb). Keep the `< Lutaml::Model::Serializable`
  # here: each sub-model requires this file first, so it can be the one
  # that defines Theme when required standalone -- drop the superclass and
  # that path defines Theme < Object, then `require "sirena/theme"` raises
  # TypeError: superclass mismatch.
  class Theme < Lutaml::Model::Serializable
    # Shared base class for every theme sub-model (color_palette.rb,
    # typography.rb, shape_styles.rb, spacing_config.rb, effect_styles.rb)
    # -- they inherit from this rather than Lutaml::Model::Serializable
    # directly, so behaviour common to all five has one home.
    class Base < Lutaml::Model::Serializable
    end
  end
end
