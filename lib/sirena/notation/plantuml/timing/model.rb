# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Timing
        # A signal. `kind` is robust, concise, clock, binary or analog; a
        # clock also has its period, pulse width and offset.
        Participant = Struct.new(:id, :title, :kind, :period, :pulse, :offset,
                                 keyword_init: true)

        # A participant taking a state at a time. `fill` and `stroke` are
        # CSS colours for a concise segment, or nil.
        Change = Struct.new(:id, :time, :state, :fill, :stroke,
                            keyword_init: true)

        # An arrow from one participant to another.
        Message = Struct.new(:from, :to, :time, :arrives, :text,
                             keyword_init: true)

        # A shaded band over every track, with an optional caption.
        Highlight = Struct.new(:from, :to, :fill, :stroke, :caption,
                               keyword_init: true)

        # Everything the source says. `pixels_per_unit` and `scale_units` are
        # nil unless a `scale` line set them; `dated` is true when times
        # are dates.
        Diagram = Struct.new(:participants, :changes, :messages, :highlights,
                             :pixels_per_unit, :dated, :scale_units,
                             keyword_init: true)
      end
    end
  end
end
