# frozen_string_literal: true

# Gaps are measured per type; each runs as `pending`, so fixing one turns
# it red until the entry is removed.
module DiagramTypeGaps
  BY_TYPE = {
    user_journey: { theme_output: "no built-in theme changes the SVG" },
    c4: { theme_output: "no built-in theme changes the SVG" },
    error: { theme_output: "no built-in theme changes the SVG" },
  }.freeze

  def self.for(type)
    BY_TYPE.fetch(type, {})
  end
end
