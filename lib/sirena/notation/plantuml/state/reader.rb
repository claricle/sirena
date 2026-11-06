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
        # deep history, or those of the state they follow. History is a state
        # labelled `H` or `H*`, which the layout draws as a circle. `scale`
        # only resizes PlantUML's output; {.scale_of} reads it for the
        # renderer. A line outside this subset raises
        # {UnsupportedConstructError}.
        class Reader
          NAME = /[A-Za-z_][A-Za-z0-9_.]*/
          MARK = /\[(?:\*|H\*?)\]/
          ARROW = /-+(?:[a-z]+-+)?>/
          FLAT = /\A-(?:right-)?>\z/
          END_STATE = /\A(?:--|\|\|)\z/
          STATE_OPEN = /\Astate[ \t]+(?:"([^"]+)"[ \t]+as[ \t]+(#{NAME})|
                         (#{NAME}))(?:[ \t]*<<([^<>]+)>>)?
                         (?:[ \t]*(\#\S+))?
                         (?:[ \t]*(\{))?(?:[ \t]*:[ \t]*(.+))?\z/xo
          TRANSITION = /\A(#{NAME}#{MARK}?|#{MARK})[ \t]*(#{ARROW})[ \t]*
                        (#{NAME}#{MARK}?|#{MARK})
                        (?:[ \t]*:[ \t]*(.+))?\z/xo
          REVERSED = /\A(#{NAME}#{MARK}?|#{MARK})[ \t]*<-+[ \t]*
                      (#{NAME}#{MARK}?|#{MARK})
                      (?:[ \t]*:[ \t]*(.+))?\z/xo
          NOTE = /\Anote[ \t]+(left|right|top|bottom)[ \t]+of[ \t]+(#{NAME})
                  (?:[ \t]*:[ \t]*(.+))?\z/xio
          END_NOTE = /\Aend[ \t]*note\z/i
          DESCRIPTION = /\A(#{NAME})[ \t]*:[ \t]*(.+)\z/o
          STYLE_BLOCK = %r{\A<style>\z}i
          END_STYLE = %r{\A</style>\z}i
          SKIN_BLOCK = /\Askinparam[ \t]+\S+[ \t]*\{\z/i
          SKIPPED = /\A(?:scale\b|title\b|hide\b|skinparam\b|left to right
                     direction\z|top to bottom direction\z)/xi
          SCALE = /\Ascale[ \t]+(\d+(?:\.\d+)?)(?:[ \t]+(width|height))?\z/i
          HISTORY = { "[H]" => ["history", "H"],
                      "[H*]" => ["deep_history", "H*"] }.freeze
          private_constant :NAME, :MARK, :ARROW, :END_STATE, :STATE_OPEN,
                           :FLAT, :TRANSITION, :REVERSED, :SCALE, :NOTE,
                           :END_NOTE,
                           :STYLE_BLOCK, :END_STYLE, :SKIN_BLOCK,
                           :DESCRIPTION, :SKIPPED, :HISTORY

          # @return [Array<Array(String, Integer)>] the stripped, non-empty,
          #   non-comment lines of the first diagram, with their numbers
          def self.lines_of(source)
            text = source.dup.force_encoding(Encoding::UTF_8).scrub
            diagram_lines(text).reject do |line, _|
              line.empty? || line.start_with?("'")
            end
          end

          # @return [Array(Float, Symbol), nil] the number of a `scale` line
          #   and what it sizes: :width, :height or :factor
          def self.scale_of(source)
            match = lines_of(source).filter_map do |line,|
              SCALE.match(line)
            end.first
            return unless match

            [match[1].to_f, (match[2] || "factor").downcase.to_sym]
          end

          def self.diagram_lines(text)
            numbered = text.lines.map.with_index { |l, i| [l.strip, i + 1] }
            body = numbered.drop_while { |line, _| !line.start_with?("@start") }
            body.drop(1).take_while { |line, _| !line.start_with?("@end") }
          end
          private_class_method :diagram_lines

          # @return [Array<Array(String, String)>] the source and target ids
          #   of each transition written with a single-dash arrow (`->`,
          #   `-right->`), which PlantUML draws on one rank, left to right
          attr_reader :flat

          # @param source [String] PlantUML source
          # @return [Sirena::Diagram::StateDiagram]
          # @raise [UnsupportedConstructError] on a line outside the subset
          # @raise [Sirena::Parser::ParseError] when a `{` is never closed
          def parse(source)
            @flat = []
            @model = Sirena::Diagram::StateDiagram.new(direction: "TB")
            @states = {}
            @scopes = [nil]
            @note = nil
            @owners = {}
            @closing = nil
            self.class.lines_of(source).each { |line| read(*line) }
            raise unclosed unless @scopes.size == 1 && @note.nil?

            @model
          end

          private

          def read(text, number)
            return note_line(text) if @note
            return if skipped?(text)
            return close_scope if text == "}"
            return if statement(text)

            raise UnsupportedConstructError.new(
              construct: "state statement", line: number, text: text,
            )
          end

          def skipped?(text)
            return skip_block(text) || true if @closing
            return open_skipped(text) || true if skipped_block?(text)

            SKIPPED.match?(text) || END_STATE.match?(text)
          end

          def skipped_block?(text)
            STYLE_BLOCK.match?(text) || SKIN_BLOCK.match?(text)
          end

          # The `skinparam x {` and `<style>` bodies are read by
          # {Style::Reader}; this reader only steps over them.
          def open_skipped(text)
            @closing = STYLE_BLOCK.match?(text) ? END_STYLE : /\A\}\z/
          end

          def skip_block(text)
            @closing = nil if @closing.match?(text)
          end

          def statement(text)
            declaration(text) || transition(text) || note(text) ||
              description(text)
          end

          # A note is one line (`note left of A : text`) or a block closed by
          # `end note`; `\n` in the text breaks a line, as PlantUML draws it.
          def note(text)
            match = NOTE.match(text)
            return unless match

            target = ensure_state(match[2])
            if match[3]
              add_note(target, match[1], match[3])
            else
              @note = [target, match[1].downcase, []]
            end
            true
          end

          def note_line(text)
            return end_note if END_NOTE.match?(text)

            @note.last << text
          end

          def end_note
            target, side, lines = @note
            @note = nil
            add_note(target, side, lines.join("<br>"))
          end

          def add_note(target, side, text)
            @model.notes << Sirena::Diagram::StateNote.new(
              id: "#{target.id}----note#{@model.notes.size}",
              text: text.gsub("\\n", "<br>").strip,
              target_id: target.id, position: side.downcase
            )
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
            adopt(state)
            state.label = match[1] if match[1]
            describe(state, match[7]) if match[7]
            @scopes.push(state) if match[6]
            true
          end

          # `state X` names where X lives: a state first met as a transition
          # target inside another body is moved to the scope that declares it.
          def adopt(state)
            parent = @scopes.last
            return if parent.equal?(owner_of(state))

            (owner_of(state)&.children || @model.states).delete(state)
            (parent ? parent.children : @model.states) << state
            @owners[state.id] = parent
          end

          def owner_of(state)
            @owners[state.id]
          end

          def transition(text)
            from, to, label, flat = parts_of(text)
            return unless from

            source = endpoint(from, :source)
            target = endpoint(to, :target)
            add_transition(source, target, label)
            @flat << [source.id, target.id] if flat
            true
          end

          # @return [Array(String, String, String, Boolean)] source, target,
          #   label as written and whether the arrow is a single-dash one;
          #   nil when the line is no transition
          def parts_of(text)
            if (match = TRANSITION.match(text))
              [match[1], match[3], match[4], FLAT.match?(match[2])]
            elsif (match = REVERSED.match(text))
              [match[2], match[1], match[3], false]
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
            @owners[id] = parent
            node
          end
        end
      end
    end
  end
end
