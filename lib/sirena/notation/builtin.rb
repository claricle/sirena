# frozen_string_literal: true

# Internal manifest: loads every built-in component of the Mermaid
# diagram types in Notation::Mermaid::TYPES. Not public API; its contents may change in any release.

# Load modules in dependency order
require_relative "../js_number"
require_relative "../source"
require_relative "../text_measurement"
require_relative "../layout/grid"
require_relative "../diagram_registry"
require_relative "mermaid"
require_relative "../theme"
require_relative "../theme/registry"
require_relative "../svg"
require_relative "../parser"
require_relative "../diagram"
require_relative "../layout"
require_relative "../renderer"
require_relative "../notation"
require_relative "../engine"

# Initialize theme registry with built-in themes
Sirena::Theme::Registry.load_builtin_themes

# Parser, layout and renderer files are named after the type's class
# (`XyChart` -> `xy_chart.rb`); the lookups in Parser.for and friends find
# the classes these files define.
Sirena::Notation::Mermaid::TYPES.each do |type, row|
  name = row[:name] || type.to_s.split("_").map(&:capitalize).join
  file = name.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase
  %w[parser layout renderer].each { |layer| require_relative "../#{layer}/#{file}" }
end

Sirena::Notation.register(Sirena::Notation::Mermaid)
