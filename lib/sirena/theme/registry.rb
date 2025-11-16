# frozen_string_literal: true

require_relative "../theme"

# Registry for pre-defined and custom themes
class Sirena::Theme::Registry
  @themes = {}

  class << self
    # Register a theme
    def register(name, theme)
      @themes[name.to_sym] = theme
    end

    # Get a theme by name
    def get(name)
      @themes[name.to_sym]
    end

    # List all registered theme names
    def list
      @themes.keys
    end

    # Load all built-in themes
    def load_builtin_themes
      builtin_dir = File.join(__dir__, "builtin")
      return unless Dir.exist?(builtin_dir)

      Dir.glob(File.join(builtin_dir, "*.yml")).each do |path|
        theme = Sirena::Theme.load(path)
        register(theme.name, theme)
      end
    end

    # Clear all registered themes (useful for testing)
    def clear
      @themes = {}
    end
  end
end