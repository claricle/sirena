# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # What the PlantUML parser returns: every class once, in order of first
      # mention, and every relation in source order. This shape is PlantUML's
      # own and is private to this notation; nothing outside
      # Sirena::Notation::PlantUML may depend on it.
      #
      # Every text field (names, member types and parameters, multiplicities,
      # labels) is the source text as written. PlantUML reads escape sequences
      # such as `\n` and creole or HTML markup inside that text; this stage
      # does not, so whatever draws the text must interpret or refuse them.
      class Diagram
        attr_reader :classes, :relations

        def initialize(classes:, relations:)
          @classes = classes
          @relations = relations
          freeze
        end

        # The parser refuses an empty wrapper, so every completed Diagram is
        # valid. Keeping the predicate here lets the shared Layout::Base own
        # the pipeline's validity guard for this notation too.
        def valid?
          !classes.empty?
        end

        def diagram_type
          :class_diagram
        end
      end
    end
  end
end
