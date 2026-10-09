# frozen_string_literal: true

require_relative "diagram"
require_relative "klass"
require_relative "member"
require_relative "note"
require_relative "relation"
require_relative "unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      # Collects what the parser reads, one line at a time, into a Diagram.
      #
      # A class mentioned in a relation before (or without) being declared
      # exists as an implicit :class. A later declaration may give it its
      # kind; redeclaring an explicitly declared class as another kind is
      # refused, because this notation cannot say what it means.
      #
      # Source with only `-->` and `<--` relations is a sequence diagram to
      # PlantUML and is refused; see `class_only?` and `GLOBAL_COMMAND`.
      class DiagramBuilder
        # The words PlantUML 1.2026.6 reads as a global command, not a
        # participant, at the start of a sequence-diagram line.
        GLOBAL_COMMAND =
          /\A(?:caption|footer|header|legend|mainframe|title)[ \t]/i

        def initialize
          @kinds = {}
          @bodies = {}
          @explicit = {}
          @relations = []
          @junctions = []
          @directives = []
          @extras = {}
          @notes = []
        end

        def directive(text)
          @directives << text
        end

        def junction(junction, number, text)
          mention(junction.owner)
          @junctions << [junction, number, text]
        end

        # @return [Array(String, Integer)] the class whose body was opened
        #   last and the line it was opened on
        def open_class
          @open
        end

        # Opens a note; its text arrives through {#add_note_line}.
        # @raise [Sirena::Parser::ParseError] when the class is unknown, as
        #   PlantUML refuses a note on a class not yet mentioned
        def open_note(head, number, lines = [])
          unless @kinds.key?(head[:target])
            raise Sirena::Parser::ParseError,
                  "Parse error: line #{number} puts a note on " \
                  "#{head[:target]}, which is not declared before it"
          end

          @note = [head, number, lines]
        end

        def add_note_line(text)
          @note.last << text
        end

        def close_note
          head, _number, lines = @note
          @notes << Note.new(head, lines: lines.freeze)
          @note = nil
        end

        # @return [Integer, nil] the line the unclosed note was opened on
        def open_note_line
          @note && @note[1]
        end

        # @return [Boolean] true until a class is declared or mentioned
        def empty?
          @kinds.empty?
        end

        # Declares a class and, when `entry[:body]` is true, opens its body.
        # `entry` holds :name, :kind, :body, :generics and :stereotypes.
        def declare(entry, number, text)
          name, kind = entry.values_at(:name, :kind)
          mention(name)
          refuse_redeclaration(name, kind, number, text)
          @kinds[name] = kind
          @explicit[name] = true
          @class_evidence = true
          @extras[name] = entry.slice(:generics, :stereotypes)
          @open = [name, number] if entry[:body]
        end

        def add_member(member)
          @bodies.fetch(@open.first) << member
        end

        def relate(relation, number, text)
          mention(relation.left)
          mention(relation.right)
          @sequence_arrow ||= [number, text] if sequence_arrow?(relation, text)
          @class_evidence ||= class_only?(relation)
          @relations << relation
        end

        # @return [Diagram] frozen, with every class once in order of first
        #   mention
        # @raise [UnsupportedConstructError] when PlantUML would read the
        #   source as a sequence diagram
        def diagram
          refuse_sequence_diagram
          @junctions.each { |entry| refuse_unrelated_junction(*entry) }

          Diagram.new(classes: build_classes.freeze,
                      relations: @relations.dup.freeze,
                      junctions: @junctions.map(&:first).freeze,
                      directives: @directives.dup.freeze,
                      notes: @notes.dup.freeze)
        end

        private

        def build_classes
          @kinds.map do |name, kind|
            body = @bodies.fetch(name).dup.freeze
            Klass.new(name: name, kind: kind, body: body,
                      **@extras.fetch(name, {}))
          end
        end

        def refuse_sequence_diagram
          return unless @sequence_arrow && !@class_evidence

          number, text = @sequence_arrow
          raise UnsupportedConstructError.new(
            construct: "sequence diagram", line: number, text: text,
          )
        end

        # PlantUML joins the two classes itself when no relation was
        # written; this notation has no relation to hang the class on.
        def refuse_unrelated_junction(junction, number, text)
          pair = [junction.from, junction.to].sort
          return if @relations.any? { |r| [r.left, r.right].sort == pair }

          raise UnsupportedConstructError.new(
            construct: "association class without its relation",
            line: number, text: text
          )
        end

        def refuse_redeclaration(name, kind, number, text)
          return unless @explicit[name] && @kinds[name] != kind

          raise UnsupportedConstructError.new(
            construct: "redeclaration as another kind", line: number,
            text: text
          )
        end

        def sequence_arrow?(relation, text)
          !class_only?(relation) && !GLOBAL_COMMAND.match?(text)
        end

        # True when only a class diagram has this relation: a multiplicity, or
        # an arrow other than a plain `-->` or `<--`.
        def class_only?(relation)
          return true if relation.left_multiplicity
          return true if relation.right_multiplicity

          !relation.plain?
        end

        def mention(name)
          @kinds[name] ||= :class
          @bodies[name] ||= []
        end
      end
    end
  end
end
