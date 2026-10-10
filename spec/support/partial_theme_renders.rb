# frozen_string_literal: true

# Renders the three palette-driven diagram types under a theme that sets one
# colour, returning each SVG's fill values.
module PartialThemeRenders
  SOURCES = [
    "sankey-beta\nA,B,10\nB,C,5\n",
    "xychart-beta\n x-axis [a, b]\n bar [1, 2]\n",
    "timeline\n title T\n 2020 : a\n 2021 : b\n",
  ].freeze

  def partial_theme_fills
    theme = { name: "mine", colors: { background: "#101010" } }
    SOURCES.map do |source|
      Sirena.render(source, theme: theme).scan(/fill="([^"]*)"/).flatten
    end
  end
end
