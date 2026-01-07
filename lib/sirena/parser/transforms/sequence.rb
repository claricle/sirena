# frozen_string_literal: true

require_relative '../../diagram/sequence'

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to Sequence diagram model.
      #
      # Converts the parse tree output from Grammars::Sequence into a
      # fully-formed Diagram::Sequence object with participants, messages,
      # notes, and activations.
      class Sequence
        # Arrow type mappings
        ARROW_TYPE_MAP = {
          '->>+' => 'solid_activate',
          '-->>+' => 'dotted_activate',
          '->>-' => 'solid_deactivate',
          '-->>-' => 'dotted_deactivate',
          '->>' => 'solid',
          '->)' => 'async',
          '-->)' => 'async_dotted',
          '->' => 'solid',
          '-->' => 'dotted'
        }.freeze

        def initialize
          @message_index = 0
          @activations = {}
        end

        # Transform parse tree into Sequence diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::Sequence] the sequence diagram model
        def apply(tree)
          diagram = Diagram::Sequence.new
          @message_index = 0
          @activations = {}

          # Tree is an array: [header, ...statements]
          if tree.is_a?(Array)
            tree.each do |item|
              next if item.is_a?(Hash) && item[:header] # Skip header
              process_statement(diagram, item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash) && tree[:statements]
            process_statements(diagram, tree[:statements])
          end

          diagram
        end

        private

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_statement(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)

          if stmt[:participant]
            add_participant(diagram, stmt, 'participant')
          elsif stmt[:actor]
            add_participant(diagram, stmt, 'actor')
          elsif stmt[:from] && stmt[:to] && stmt[:arrow]
            add_message(diagram, stmt)
          elsif stmt[:position] && stmt[:note_text]
            add_note(diagram, stmt)
          elsif stmt[:activate]
            track_activation(diagram, stmt[:activate].to_s, true)
          elsif stmt[:deactivate]
            track_activation(diagram, stmt[:deactivate].to_s, false)
          elsif stmt[:box_label]
            process_box(diagram, stmt)
          elsif stmt[:loop_label]
            process_loop(diagram, stmt)
          elsif stmt[:alt_label]
            process_alt(diagram, stmt)
          elsif stmt[:opt_label]
            process_opt(diagram, stmt)
          elsif stmt[:par_label]
            process_par(diagram, stmt)
          elsif stmt[:critical_label]
            process_critical(diagram, stmt)
          elsif stmt[:break_label]
            process_break(diagram, stmt)
          end
        end

        def add_participant(diagram, stmt, actor_type)
          id = stmt[:id].to_s
          label = if stmt[:label]
                    extract_text(stmt[:label])
                  else
                    id
                  end

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
          from_id = stmt[:from].to_s
          to_id = stmt[:to].to_s
          message_text = stmt[:text] ? extract_text(stmt[:text]) : ''

          # Determine arrow type
          arrow = stmt[:arrow]
          arrow_str = if arrow.is_a?(Hash)
                        if arrow[:arrow_activation]
                          arrow[:arrow_activation].to_s
                        elsif arrow[:arrow_plain]
                          arrow[:arrow_plain].to_s
                        else
                          arrow.values.first.to_s
                        end
                      else
                        arrow.to_s
                      end

          arrow_type = ARROW_TYPE_MAP[arrow_str] || 'solid'

          # Ensure participants exist
          ensure_participant(diagram, from_id)
          ensure_participant(diagram, to_id)

          # Handle activation modifiers
          handle_arrow_activation(diagram, from_id, to_id, arrow_str)

          message = Diagram::SequenceMessage.new.tap do |m|
            m.from_id = from_id
            m.to_id = to_id
            m.message_text = message_text
            m.arrow_type = arrow_type.sub(/_activate$/, '').sub(/_deactivate$/, '')
          end

          diagram.messages << message
          @message_index += 1
        end

        def handle_arrow_activation(diagram, from_id, to_id, arrow_str)
          if arrow_str.end_with?('+')
            # Activate target (receiver)
            track_activation(diagram, to_id, true)
          elsif arrow_str.end_with?('-')
            # Deactivate source (sender)
            track_activation(diagram, from_id, false)
          end
        end

        def add_note(diagram, stmt)
          position_data = stmt[:position]
          position = if position_data.is_a?(Hash)
                       if position_data[:left_of]
                         'left_of'
                       elsif position_data[:right_of]
                         'right_of'
                       elsif position_data[:over]
                         'over'
                       else
                         'over'
                       end
                     else
                       'over'
                     end

          participants = if stmt[:participants].is_a?(Array)
                           stmt[:participants].map do |p|
                             p.is_a?(Hash) ? p[:participant].to_s : p.to_s
                           end
                         elsif stmt[:participants].is_a?(Hash)
                           [stmt[:participants][:participant].to_s]
                         else
                           []
                         end

          text = extract_text(stmt[:note_text])

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
          ensure_participant(diagram, participant_id)

          @activations[participant_id] ||= []

          if activate
            # Start new activation
            @activations[participant_id] << { start: @message_index }
          else
            # End latest activation
            active = @activations[participant_id].last
            if active && !active[:end]
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
        end

        def process_box(diagram, stmt)
          # Box statements contain nested participants/messages
          # Process the nested statements
          if stmt[:box_statements]
            process_statements(diagram, stmt[:box_statements])
          end
        end

        def process_loop(diagram, stmt)
          # Process loop statements
          if stmt[:loop_statements]
            process_statements(diagram, stmt[:loop_statements])
          end
        end

        def process_alt(diagram, stmt)
          # Process alt statements
          if stmt[:alt_statements]
            process_statements(diagram, stmt[:alt_statements])
          end

          # Process else blocks
          if stmt[:else_blocks]
            Array(stmt[:else_blocks]).each do |else_block|
              if else_block[:else_statements]
                process_statements(diagram, else_block[:else_statements])
              end
            end
          end
        end

        def process_opt(diagram, stmt)
          # Process opt statements
          if stmt[:opt_statements]
            process_statements(diagram, stmt[:opt_statements])
          end
        end

        def process_par(diagram, stmt)
          # Process par statements
          if stmt[:par_statements]
            process_statements(diagram, stmt[:par_statements])
          end

          # Process and blocks
          if stmt[:and_blocks]
            Array(stmt[:and_blocks]).each do |and_block|
              if and_block[:and_statements]
                process_statements(diagram, and_block[:and_statements])
              end
            end
          end
        end

        def process_critical(diagram, stmt)
          # Process critical statements
          if stmt[:critical_statements]
            process_statements(diagram, stmt[:critical_statements])
          end

          # Process option blocks
          if stmt[:option_blocks]
            Array(stmt[:option_blocks]).each do |option_block|
              if option_block[:option_statements]
                process_statements(diagram, option_block[:option_statements])
              end
            end
          end
        end

        def process_break(diagram, stmt)
          # Process break statements
          if stmt[:break_statements]
            process_statements(diagram, stmt[:break_statements])
          end
        end

        def ensure_participant(diagram, participant_id)
          return if diagram.find_participant(participant_id)

          participant = Diagram::SequenceParticipant.new.tap do |p|
            p.id = participant_id
            p.label = participant_id
            p.actor_type = 'participant'
          end

          diagram.participants << participant
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            elsif value[:message_text]
              value[:message_text].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end.strip
        end
      end
    end
  end
end