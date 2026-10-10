# frozen_string_literal: true

require_relative "capture_string"
require_relative "../../diagram/sequence"
require_relative "sequence_blocks"

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
        include SequenceBlocks

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

        STATEMENT_HANDLERS = [
          [%i[participant], :add_participant_statement],
          [%i[actor], :add_actor_statement],
          [%i[destroy], :destroy_participant],
          [%i[links], :link_participant],
          [%i[from to arrow], :add_message],
          [%i[position note_text], :add_note],
          [%i[activate], :activate_participant],
          [%i[deactivate], :deactivate_participant],
          [%i[box_label], :process_box],
          [%i[loop_label], :process_loop],
          [%i[alt_label], :process_alt],
          [%i[opt_label], :process_opt],
          [%i[rect_label], :process_rect],
          [%i[par_label], :process_par],
          [%i[critical_label], :process_critical],
          [%i[break_label], :process_break],
        ].freeze
        private_constant :STATEMENT_HANDLERS

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
          reset_blocks
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
          entry = STATEMENT_HANDLERS.find do |keys, _handler|
            keys.all? { |key| stmt[key] }
          end
          send(entry.last, diagram, stmt) if entry
        end

        def add_participant_statement(diagram, stmt)
          add_participant(diagram, stmt, "participant")
        end

        def add_actor_statement(diagram, stmt)
          add_participant(diagram, stmt, "actor")
        end

        def destroy_participant(_diagram, stmt)
          register_destroyed(actor_id(stmt[:destroy]))
        end

        def link_participant(diagram, stmt)
          ensure_participant(diagram, actor_id(stmt[:links]))
        end

        def activate_participant(diagram, stmt)
          track_activation(diagram, actor_id(stmt[:activate]), true)
        end

        def deactivate_participant(diagram, stmt)
          track_activation(diagram, actor_id(stmt[:deactivate]), false)
        end

        def add_participant(diagram, stmt, actor_type)
          id = actor_id(stmt[:id])
          @known_actor_ids << id
          @box_ids&.push(id)
          label = participant_label(id, stmt[:label])
          existing = diagram.find_participant(id)
          return update_participant(existing, label, actor_type) if existing

          diagram.participants << participant(id, label, actor_type)
        end

        def participant_label(id, captured_label)
          shown_id = Diagram::SequenceText.decode(id)
          label = captured_label ? decoded_text(captured_label) : shown_id
          label.empty? ? shown_id : label
        end

        def participant(id, label, actor_type)
          Diagram::SequenceParticipant.new.tap do |item|
            item.id = id
            item.label = label
            item.actor_type = actor_type
          end
        end

        def update_participant(participant, label, actor_type)
          participant.label = label unless label.empty?
          participant.actor_type = actor_type
        end

        def add_message(diagram, stmt)
          check_lifecycle!(stmt)
          data = message_data(stmt)
          ensure_participant(diagram, data[:from_id])
          ensure_participant(diagram, data[:to_id])
          handle_arrow_activation(diagram, data[:from_id], data[:to_id],
                                  activation(stmt[:arrow]))
          diagram.messages << sequence_message(data)
          @message_index += 1
        end

        def message_data(stmt)
          styles = ARROW_STYLES.fetch(
            arrow_base(stmt[:arrow]), %w[solid filled target]
          )
          {
            from_id: actor_id(stmt[:from]),
            to_id: actor_id(stmt[:to]),
            message_text: extract_text(stmt[:text]),
            line_style: styles[0], head_style: styles[1], head_side: styles[2]
          }
        end

        def sequence_message(data)
          Diagram::SequenceMessage.new.tap do |message|
            data.each do |attribute, value|
              message.public_send("#{attribute}=", value)
            end
          end
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
            validate_created!(to_id)
            @pending_created = nil
          elsif @pending_destroyed
            validate_destroyed!(from_id, to_id)
            @pending_destroyed = nil
          end
        end

        def validate_created!(to_id)
          return if to_id == @pending_created

          raise Parser::ParseError,
                "The created participant #{@pending_created} does not " \
                "have an associated creating message after its " \
                "declaration. Please check the sequence diagram."
        end

        def validate_destroyed!(from_id, to_id)
          return if [from_id, to_id].include?(@pending_destroyed)

          raise Parser::ParseError,
                "The destroyed participant #{@pending_destroyed} does " \
                "not have an associated destroying message after its " \
                "declaration. Please check the sequence diagram."
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
          participants = note_participants(stmt)
          participants.each { |pid| ensure_participant(diagram, pid) }
          diagram.notes << sequence_note(stmt, participants)
        end

        def note_position(position)
          return "left_of" if position[:left_of]
          return "right_of" if position[:right_of]

          "over"
        end

        def note_participants(stmt)
          captures = stmt[:participants]
          captures = [captures] unless captures.is_a?(Array)
          captures.map { |item| actor_id(item[:participant]) }
        end

        def sequence_note(stmt, participants)
          Diagram::SequenceNote.new.tap do |note|
            note.text = decoded_text(stmt[:note_text])
            note.position = note_position(stmt[:position])
            note.participant_ids = participants
            note.message_index = @message_index
            note.order = next_order
          end
        end

        def track_activation(diagram, participant_id, activate)
          ensure_participant(diagram, participant_id, track: false)
          @activations[participant_id] ||= []
          return open_activation(participant_id) if activate

          close_activation(diagram, participant_id)
        end

        def open_activation(participant_id)
          @activations[participant_id] << { start: @message_index }
        end

        def close_activation(diagram, participant_id)
          active = @activations[participant_id].reverse.find do |item|
            !item[:end]
          end
          refuse_inactive_participant(participant_id) unless active
          active[:end] = @message_index
          diagram.activations << activation_record(participant_id, active)
        end

        def refuse_inactive_participant(participant_id)
          raise Parser::ParseError,
                "Trying to deactivate an inactive participant " \
                "(#{participant_id})"
        end

        def activation_record(participant_id, active)
          Diagram::SequenceActivation.new.tap do |activation|
            activation.participant_id = participant_id
            activation.start_index = active[:start]
            activation.end_index = active[:end]
          end
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
