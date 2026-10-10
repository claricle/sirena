# frozen_string_literal: true

require_relative "capture_string"
require_relative "../../diagram/sequence"

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to Sequence diagram model.
      #
      # Converts the parse tree output from Grammars::Sequence into a
      # fully-formed Diagram::Sequence object with participants, messages,
      # notes, and activations.
      class Sequence
        include CaptureString

        # Every arrow mmdc 11.12.0 renders, read off its own SVG: a line
        # class (messageLine0/1 -> solid/dotted), a marker, and which end
        # of the line carries it. The reversed spellings differ from their
        # forward twin only in that last axis — `\\-` puts the same head
        # mermaid gives `-\\` on the source end instead.
        ARROW_STYLES = {
          "->" => %w[solid none target],
          "-->" => %w[dotted none target],
          "->>" => %w[solid filled target],
          "-->>" => %w[dotted filled target],
          "-x" => %w[solid cross target],
          "--x" => %w[dotted cross target],
          "-X" => %w[solid cross target],
          "--X" => %w[dotted cross target],
          "-)" => %w[solid open target],
          "--)" => %w[dotted open target],
          "-|/" => %w[solid half_bottom target],
          "--|/" => %w[dotted half_bottom target],
          "-|\\" => %w[solid half_top target],
          "--|\\" => %w[dotted half_top target],
          "-//" => %w[solid stick_bottom target],
          "--//" => %w[dotted stick_bottom target],
          "-\\\\" => %w[solid stick_top target],
          "--\\\\" => %w[dotted stick_top target],
          "/|-" => %w[solid half_bottom source],
          "/|--" => %w[dotted half_bottom source],
          '\\|-' => %w[solid half_top source],
          '\\|--' => %w[dotted half_top source],
          "//-" => %w[solid stick_bottom source],
          "//--" => %w[dotted stick_bottom source],
          '\\\\-' => %w[solid stick_top source],
          '\\\\--' => %w[dotted stick_top source],
          "<<->>" => %w[solid filled both],
          "<<-->>" => %w[dotted filled both],
        }.freeze

        # Transform parse tree into Sequence diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::Sequence] the sequence diagram model
        def apply(tree)
          diagram = Diagram::Sequence.new
          reset_state

          # Tree is an array: [header, ...statements]
          if tree.is_a?(Array)
            tree.each do |item|
              next if item[:header] # Skip header

              process_statement(diagram, item)
            end
          end

          diagram
        end

        private

        # Called at the start of `apply`, so a builder is reusable across
        # multiple `parse` calls without carrying state from the last one —
        # a single place to add a new per-parse ivar.
        def reset_state
          @message_index = 0
          @activations = {}
          @pending_created = nil
          @pending_destroyed = nil
          @known_actor_ids = Set.new
        end

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_statement(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_statement(diagram, stmt)
          # `create` applies on top of the `participant`/`actor` branch
          # below, not instead of it (`create_statement` delegates to the
          # same declaration rules, so both keys are set on one `stmt`) —
          # checked here, before the dispatch below adds the participant,
          # because the duplicate-id check needs the id to still be
          # absent from `@known_actor_ids`.
          register_created(actor_id(stmt[:id])) if stmt[:create]

          if stmt[:participant]
            add_participant(diagram, stmt, "participant")
          elsif stmt[:actor]
            add_participant(diagram, stmt, "actor")
          elsif stmt[:destroy]
            register_destroyed(actor_id(stmt[:destroy]))
          elsif stmt[:links]
            ensure_participant(diagram, actor_id(stmt[:links]))
          elsif stmt[:from] && stmt[:to] && stmt[:arrow]
            add_message(diagram, stmt)
          elsif stmt[:position] && stmt[:note_text]
            add_note(diagram, stmt)
          elsif stmt[:activate]
            track_activation(diagram, actor_id(stmt[:activate]), true)
          elsif stmt[:deactivate]
            track_activation(diagram, actor_id(stmt[:deactivate]), false)
          elsif stmt[:box_label]
            process_box(diagram, stmt)
          elsif stmt[:loop_label]
            process_loop(diagram, stmt)
          elsif stmt[:alt_label]
            process_alt(diagram, stmt)
          elsif stmt[:opt_label]
            process_opt(diagram, stmt)
          elsif stmt[:rect_label]
            process_rect(diagram, stmt)
          elsif stmt[:par_label]
            process_par(diagram, stmt)
          elsif stmt[:critical_label]
            process_critical(diagram, stmt)
          elsif stmt[:break_label]
            process_break(diagram, stmt)
          end
        end

        def add_participant(diagram, stmt, actor_type)
          id = actor_id(stmt[:id])
          @known_actor_ids << id
          shown_id = Diagram::SequenceText.decode(id)
          label = stmt[:label] ? decoded_text(stmt[:label]) : shown_id
          label = shown_id if label.empty?

          participant = Diagram::SequenceParticipant.new.tap do |p|
            p.id = id
            p.label = label
            p.actor_type = actor_type
          end

          # Add or update participant
          existing = diagram.find_participant(id)
          if existing
            existing.label = label unless label.empty?
            existing.actor_type = actor_type
          else
            diagram.participants << participant
          end
        end

        def add_message(diagram, stmt)
          check_lifecycle!(stmt)

          from_id = actor_id(stmt[:from])
          to_id = actor_id(stmt[:to])
          message_text = extract_text(stmt[:text])

          base = arrow_base(stmt[:arrow])
          line_style, head_style, head_side =
            ARROW_STYLES.fetch(base, %w[solid filled target])

          # Ensure participants exist
          ensure_participant(diagram, from_id)
          ensure_participant(diagram, to_id)

          handle_arrow_activation(diagram, from_id, to_id,
                                  activation(stmt[:arrow]))

          message = Diagram::SequenceMessage.new.tap do |m|
            m.from_id = from_id
            m.to_id = to_id
            m.message_text = message_text
            m.line_style = line_style
            m.head_style = head_style
            m.head_side = head_side
          end

          diagram.messages << message
          @message_index += 1
        end

        # mermaid rejects a `create` whose id already belongs to an actor,
        # whether that actor arrived by declaration, a message, a note or
        # a `links` line — `@known_actor_ids` tracks exactly that set.
        # `diagram.participants` is NOT the same set: `track_activation`
        # also adds to it (for rendering an activated lifeline), but an
        # `activate`/`deactivate` reference introduces no actor on
        # mermaid's side, so it must not trip this check.
        def register_created(id)
          if @known_actor_ids.include?(id)
            raise Parser::ParseError,
                  "It is not possible to have actors with the same id, " \
                  "even if one is destroyed before the next is created (#{id})."
          end

          @pending_created = id
        end

        def register_destroyed(id)
          @pending_destroyed = id
        end

        # Ports mermaid's own `apply()` create/destroy check verbatim: a
        # single pending slot per kind, checked and cleared on the very
        # NEXT message — nothing else (a note, an activation, a nested
        # block boundary) consumes or clears it. `create` takes priority
        # over a still-pending `destroy`, matching mermaid's own
        # `if (lastCreated) {...} else if (lastDestroyed) {...}`.
        def check_lifecycle!(stmt)
          to_id = actor_id(stmt[:to])
          from_id = actor_id(stmt[:from])

          if @pending_created
            unless to_id == @pending_created
              raise Parser::ParseError,
                    "The created participant #{@pending_created} does not " \
                    "have an associated creating message after its " \
                    "declaration. Please check the sequence diagram."
            end
            @pending_created = nil
          elsif @pending_destroyed
            unless to_id == @pending_destroyed || from_id == @pending_destroyed
              raise Parser::ParseError,
                    "The destroyed participant #{@pending_destroyed} does " \
                    "not have an associated destroying message after its " \
                    "declaration. Please check the sequence diagram."
            end
            @pending_destroyed = nil
          end
        end

        def arrow_base(arrow)
          arrow[:arrow_base].to_s
        end

        def activation(arrow)
          # Stripped: mermaid allows whitespace before the suffix, so the
          # capture can arrive as " +" and never matched a bare "+".
          arrow[:activation].to_s.strip
        end

        def handle_arrow_activation(diagram, from_id, to_id, suffix)
          case suffix
          when "+" then track_activation(diagram, to_id, true)
          when "-" then track_activation(diagram, from_id, false)
          end
        end

        def add_note(diagram, stmt)
          position_data = stmt[:position]
          position = if position_data[:left_of]
                       "left_of"
                     elsif position_data[:right_of]
                       "right_of"
                     else
                       "over"
                     end

          participants = if stmt[:participants].is_a?(Array)
                           stmt[:participants].map do |p|
                             actor_id(p[:participant])
                           end
                         else
                           [actor_id(stmt[:participants][:participant])]
                         end

          text = decoded_text(stmt[:note_text])

          # Ensure participants exist
          participants.each { |pid| ensure_participant(diagram, pid) }

          note = Diagram::SequenceNote.new.tap do |n|
            n.text = text
            n.position = position
            n.participant_ids = participants
            n.message_index = @message_index
          end

          diagram.notes << note
        end

        def track_activation(diagram, participant_id, activate)
          ensure_participant(diagram, participant_id, track: false)

          @activations[participant_id] ||= []

          if activate
            # Start new activation
            @activations[participant_id] << { start: @message_index }
          else
            # Close the most recent activation still open — a stack, not
            # simply the last entry. Two `+` on the same participant
            # followed by two `-` is ordinary mermaid, and reading only the
            # last entry closed the same one twice.
            active = @activations[participant_id].reverse.find { |a| !a[:end] }

            if active.nil?
              # mmdc rejects a source that deactivates a participant with
              # nothing open. Ignoring it silently rendered arrow forms
              # mermaid refuses, such as `A-x-B`.
              raise Parser::ParseError,
                    "Trying to deactivate an inactive participant " \
                    "(#{participant_id})"
            end

            active[:end] = @message_index

            # Create activation record
            activation = Diagram::SequenceActivation.new.tap do |a|
              a.participant_id = participant_id
              a.start_index = active[:start]
              a.end_index = active[:end]
            end

            diagram.activations << activation
          end
        end

        # Each block rule names its statement list with `.as`, so the key is
        # always present; the else/and/option continuations are a named
        # `repeat` (an Array, possibly empty) of hashes that name theirs.
        def process_box(diagram, stmt)
          process_statements(diagram, stmt[:box_statements])
        end

        def process_loop(diagram, stmt)
          process_statements(diagram, stmt[:loop_statements])
        end

        def process_alt(diagram, stmt)
          process_statements(diagram, stmt[:alt_statements])
          stmt[:else_blocks].each do |block|
            process_statements(diagram, block[:else_statements])
          end
        end

        def process_opt(diagram, stmt)
          process_statements(diagram, stmt[:opt_statements])
        end

        def process_rect(diagram, stmt)
          process_statements(diagram, stmt[:rect_statements])
        end

        def process_par(diagram, stmt)
          process_statements(diagram, stmt[:par_statements])
          stmt[:and_blocks].each do |block|
            process_statements(diagram, block[:and_statements])
          end
        end

        def process_critical(diagram, stmt)
          process_statements(diagram, stmt[:critical_statements])
          stmt[:option_blocks].each do |block|
            process_statements(diagram, block[:option_statements])
          end
        end

        def process_break(diagram, stmt)
          process_statements(diagram, stmt[:break_statements])
        end

        # An actor name is a bounded run of text, so a name that abuts a
        # comma, colon or arrow (`participant A `, `Note over A , B: n`)
        # carries the surrounding whitespace into the capture. Every
        # capture site normalises through here rather than duplicating
        # `.strip`, because each is reachable from legal mermaid and each
        # unstripped id creates a phantom duplicate participant.
        #
        # The id stays as written: mmdc keeps `participant EA` and
        # `E#65;` as two actors and decodes only the text it draws.
        def actor_id(slice) = slice.to_s.strip

        # `track:` is false only from `track_activation`: an `activate`/
        # `deactivate` reference introduces a participant for RENDERING
        # (mermaid draws the lifeline either way), but not for mermaid's
        # own actor bookkeeping — its `activeStart` record adds no actor,
        # so `register_created`'s duplicate-id check must not see one
        # either (measured against mermaid 11.16.1: `activate C\ncreate
        # participant C\nA->>C: m` is accepted there).
        def ensure_participant(diagram, participant_id, track: true)
          @known_actor_ids << participant_id if track

          return if diagram.find_participant(participant_id)

          participant = Diagram::SequenceParticipant.new.tap do |p|
            p.id = participant_id
            p.label = Diagram::SequenceText.decode(participant_id)
            p.actor_type = "participant"
          end

          diagram.participants << participant
        end

        # Message text is decoded later, by `SequenceText.display`, which
        # also drops `wrap:` and turns `<br>` into a space; labels and notes
        # have no later step.
        def decoded_text(value)
          Diagram::SequenceText.decode(extract_text(value))
        end

        # `message_text` is a Slice when non-empty and `[]` (Parslet's
        # empty-repeat capture) when empty, so `[]` always means empty.
        # It has to be recursed into rather than `.to_s`'d directly: the
        # Hash arm receives `{message_text: []}`, and `[]` is truthy in
        # Ruby, so a naive `value[:message_text].to_s` renders the literal
        # two-character string "[]" instead of reaching the Array branch.
        def extract_text(value)
          case value
          when Hash
            if value[:string]
              capture_string(value[:string])
            else
              extract_text(value[:message_text])
            end
          when Array then ""
          else value.to_s
          end.strip
        end
      end
    end
  end
end
