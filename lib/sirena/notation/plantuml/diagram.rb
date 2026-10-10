# frozen_string_literal: true

require_relative "package"

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
        attr_reader :classes, :relations, :junctions, :directives, :notes,
                    :packages

        # `junctions` are the association classes, `directives` the
        # restyling lines the parser recorded without applying and `notes`
        # the Notes in source order. `packages` are the Packages in source
        # order; each class names its own.
        # @param recorded [Hash] optional `:junctions`, `:directives` and
        #   `:notes`; each defaults to empty
        def initialize(classes:, relations:, packages: [].freeze, **recorded)
          @classes = classes
          @relations = relations
          @packages = packages
          @junctions = recorded.fetch(:junctions, [].freeze)
          @directives = recorded.fetch(:directives, [].freeze)
          @notes = recorded.fetch(:notes, [].freeze)
          freeze
        end

        # The parser refuses an empty wrapper, so every completed Diagram is
        # valid. Keeping the predicate here lets the shared Layout::Base own
        # the pipeline's validity guard for this notation too.
        def valid?
          !classes.empty?
        end

        # @see Package.chain
        def package_chain(id)
          Package.chain(id, packages)
        end

        def diagram_type
          :class_diagram
        end
      end
    end
  end
end
