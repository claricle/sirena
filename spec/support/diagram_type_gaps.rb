# frozen_string_literal: true

# Gaps are measured per type; each runs as `pending`, so fixing one turns
# it red until the entry is removed.
module DiagramTypeGaps
  BY_TYPE = {
    timeline: {
      theme_output: "cards use mmdc's fixed default-theme palette",
    },
  }.freeze

  def self.for(type)
    BY_TYPE.fetch(type, {})
  end
end
