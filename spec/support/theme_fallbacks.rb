# frozen_string_literal: true

# Pairs every `theme_color(:key) || "literal"` under lib/ with its literal.
# Both quote styles count: most `border_color` sites are single-quoted.
module ThemeFallbacks
  ASKED_CALL = /theme_color\(:([a-z_]+)\)/
  FALLBACK_CALL = /theme_color\(:([a-z_]+)\)\s*\|\|\s*["']([^"']+)["']/

  def theme_fallbacks
    Dir.glob("lib/**/*.rb").each_with_object(Hash.new { [] }) do |path, pairs|
      File.read(path).scan(FALLBACK_CALL) do |key, colour|
        pairs[key.to_sym] |= [colour]
      end
    end
  end

  # Every key a renderer asks the theme for, with or without a fallback.
  def theme_keys_asked
    Dir.glob("lib/**/*.rb").flat_map do |path|
      File.read(path).scan(ASKED_CALL).flatten.map(&:to_sym)
    end.uniq
  end

  def builtin_themes
    %i[default dark light high_contrast].map do |name|
      Sirena::Theme::Registry.get(name)
    end
  end
end
