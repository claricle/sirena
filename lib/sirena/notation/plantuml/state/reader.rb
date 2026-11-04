# frozen_string_literal: true

require_relative "../../../diagram/state_diagram"
require_relative "../../../error/parse_error"
require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module State
        # Reads PlantUML state-diagram source into the StateDiagram model.
        #
        # A state belongs to the scope that first mentions it. `[*]` is the
        # start of the scope when it begins a transition and the end of the
        # scope when it ends one; `[H]` and `[H*]` are the scope's shallow and
        # deep history, or those of the state they follow. History has no
        # shape of its own in the model, so it is drawn as a small state
        # labelled `H` or `H*`. `scale` only resizes PlantUML's output and is
        # read and dropped. A line outside this subset raises
        # {UnsupportedConstructError}.
        class Reader
          NAME = /[A-Za-z_][A-Za-z0-9_.]*/
          MARK = /\[(?:\*|H\*?)\]/
          ARROW = /-+(?:[a-z]+-+)?>/
          END_STATE = /\A(?:--|\|\|)\z/
          STATE_OPEN = /\Astate[ \t]+(?:"([^"]+)"[ \t]+as[ \t]+(#{NAME})|
                         (#{NAME}))(?:[ \t]*<<[^<>]+>>)?
                         (?:[ \t]*(\{))?(?:[ \t]*:[ \t]*(.+))?\z/xo
          TRANSITION = /\A(#{NAME}#{MARK}?|#{MARK})[ \t]*(#{ARROW})[ \t]*
                        (#{NAME}#{MARK}?|#{MARK})
                        (?:[ \t]*:[ \t]*(.+))?\z/xo
          REVERSED = /\A(#{NAME}#{MARK}?|#{MARK})[ \t]*<-+[ \t]*
                      (#{NAME}#{MARK}?|#{MARK})
                      (?:[ \t]*:[ \t]*(.+))?\z/xo
          DESCRIPTION = /\A(#{NAME})[ \t]*:[ \t]*(.+)\z/o
          SKIPPED = /\A(?:scale\b|title\b|hide\b|skinparam\b|left to right
                     direction\z|top to bottom direction\z)/xi
          HISTORY = { "[H]" => ["history", "H"],
                      "[H*]" => ["deep_history", "H*"] }.freeze
          private_constant :NAME, :MARK, :ARROW, :END_STATE, :STATE_OPEN,
                           :TRANSITION, :REVERSED, :DESCRIPTION, :SKIPPED,
                           :HISTORY

          # @return [Array<Array(String, Integer)>] the stripped, non-empty,
          #   non-comment lines of the first diagram, with their numbers
          def self.lines_of(source)
            text = source.dup.force_encoding(Encoding::UTF_8).scrub
            diagram_lines(text).reject do |line, _|
              line.empty? || line.start_with?("'")
            end
          end

          def self.diagram_lines(text)
            numbered = text.lines.map.with_index { |l, i| [l.strip, i + 1] }
            body = numbered.drop_while { |line, _| !line.start_with?("@start") }
            body.drop(1).take_while { |line, _| !line.start_with?("@end") }
          end
          private_class_method :diagram_lines

          # @param source [String] PlantUML source
          # @return [Sirena::Diagram::StateDiagram]
          # @raise [UnsupportedConstructError] on a line outside the subset
          # @raise [Sirena::Parser::ParseError] when a `{` is never closed
          def parse(source)
            @model = Sirena::Diagram::StateDiagram.new(direction: "TB")
            @states = {}
            @scopes = [nil]
            self.class.lines_of(source).each { |line| read(*line) }
            raise unclosed unless @scopes.size == 1

            @model
          end

          private

          def read(text, number)
            return if SKIPPED.match?(text) || END_STATE.match?(text)
            return close_scope if text == "}"
            return if statement(text)

            raise UnsupportedConstructError.new(
              construct: "state statement", line: number, text: text,
            )
          end

          def statement(text)
            declaration(text) || transition(text) || description(text)
          end

          def unclosed
            Sirena::Parser::ParseError.new(
              "Parse error: a state body is never closed with }",
            )
          end

          def close_scope
            @scopes.pop if @scopes.size > 1
          end

          def declaration(text)
            match = STATE_OPEN.match(text)
            return unless match

            state = ensure_state(match[2] || match[3])
            state.label = match[1] if match[1]
            describe(state, match[5]) if match[5]
            @scopes.push(state) if match[4]
            true
          end

          def transition(text)
            from, to, label = parts_of(text)
            return unless from

            add_transition(endpoint(from, :source), endpoint(to, :target),
                           label)
            true
          end

          # @return [Array(String, String, String)] source, target and label
          #   as written; nil when the line is no transition
          def parts_of(text)
            if (match = TRANSITION.match(text))
              [match[1], match[3], match[4]]
            elsif (match = REVERSED.match(text))
              [match[2], match[1], match[3]]
            end
          end

          def description(text)
            match = DESCRIPTION.match(text)
            return unless match

            describe(ensure_state(match[1]), match[2])
            true
          end

          def describe(state, text)
            state.description = text
            state.descriptions = [*titled(state), text]
          end

          # A described state keeps its name as the first line, as PlantUML
          # draws it.
          def titled(state)
            state.descriptions.empty? ? [state.label] : state.descriptions
          end

          def add_transition(from, to, label)
            @model.transitions << Sirena::Diagram::StateTransition.new(
              from_id: from.id, to_id: to.id, trigger: label,
            )
          end

          def endpoint(written, role)
            marker = written[MARK]
            return ensure_state(written) unless marker

            owner = written.delete_suffix(marker)
            marker_state(marker, role,
                         (ensure_state(owner) unless owner.empty?))
          end

          def marker_state(marker, role, owner)
            return history_state(marker, owner) if HISTORY.key?(marker)

            kind = role == :source ? "start" : "end"
            special("#{scope_id}_#{kind}", "[*]", kind, @scopes.last)
          end

          def history_state(marker, owner)
            kind, label = HISTORY.fetch(marker)
            parent = owner || @scopes.last
            id = "#{parent&.id || 'root'}_#{kind}"
            special(id, label, "normal", parent)
          end

          def scope_id
            @scopes.last&.id || "root"
          end

          def special(id, label, type, parent)
            @states[id] ||= build_state(id, label, type, parent)
          end

          def ensure_state(id)
            @states[id] ||= build_state(id, id, "normal", @scopes.last)
          end

          def build_state(id, label, type, parent)
            node = Sirena::Diagram::StateNode.new(
              id: id, label: label, state_type: type,
            )
            (parent ? parent.children : @model.states) << node
            node
          end
        end
      end
    end
  end
end
