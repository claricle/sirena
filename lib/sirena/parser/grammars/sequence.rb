# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for sequence diagrams.
      #
      # Handles all sequence diagram syntax including participants, messages,
      # notes, activations, and control structures. The grammar properly handles
      # complex arrow patterns with activation modifiers that cannot be parsed
      # correctly by regex-based lexers.
      class Sequence < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        rule(:header) do
          str('sequenceDiagram').as(:header) >> ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          participant_declaration |
            actor_declaration |
            note_statement |
            box_statement |
            activation_command |
            deactivation_command |
            control_structure |
            message
        end

        # Participant declarations
        rule(:participant_declaration) do
          str('participant') >> space.repeat(1) >>
            identifier.as(:id) >> space? >>
            (str('as') >> space.repeat(1) >> label.as(:label)).maybe >>
            line_end.as(:participant)
        end

        rule(:actor_declaration) do
          str('actor') >> space.repeat(1) >>
            identifier.as(:id) >> space? >>
            (str('as') >> space.repeat(1) >> label.as(:label)).maybe >>
            line_end.as(:actor)
        end

        # Messages with arrows (order matters: longest patterns first)
        rule(:message) do
          identifier.as(:from) >> space? >>
            arrow.as(:arrow) >> space? >>
            identifier.as(:to) >> space? >>
            message_text.maybe.as(:text) >>
            line_end
        end

        # Arrow types including activation modifiers
        # Critical: These must be tried in order from longest to shortest
        rule(:arrow) do
          arrow_with_activation | arrow_without_activation
        end

        rule(:arrow_with_activation) do
          (
            str('->>+') | str('-->>+') |
            str('->>-') | str('-->>-')
          ).as(:arrow_activation)
        end

        rule(:arrow_without_activation) do
          (
            str('->>') >> str('+').absent? >> str('-').absent? |
            str('-->>') >> str('+').absent? >> str('-').absent? |
            str('->)') | str('-->)') |
            str('->') | str('-->')
          ).as(:arrow_plain)
        end

        rule(:message_text) do
          colon >> space? >>
            (line_end.absent? >> any).repeat.as(:message_text)
        end

        # Notes
        rule(:note_statement) do
          (str('note') | str('Note')) >> space.repeat(1) >>
            note_position.as(:position) >> space.repeat(1) >>
            note_participants.as(:participants) >> space? >>
            colon >> space? >>
            (line_end.absent? >> any).repeat.as(:note_text) >>
            line_end
        end

        rule(:note_position) do
          (str('left') >> space.repeat(1) >> str('of')).as(:left_of) |
            (str('right') >> space.repeat(1) >> str('of')).as(:right_of) |
            str('over').as(:over)
        end

        rule(:note_participants) do
          identifier.as(:participant) >>
            (space? >> comma >> space? >>
             identifier.as(:participant)).repeat
        end

        # Activation/Deactivation commands
        rule(:activation_command) do
          str('activate') >> space.repeat(1) >>
            identifier.as(:activate) >>
            line_end
        end

        rule(:deactivation_command) do
          str('deactivate') >> space.repeat(1) >>
            identifier.as(:deactivate) >>
            line_end
        end

        # Box grouping
        rule(:box_statement) do
          str('box') >> space.repeat(1) >>
            (line_end.absent? >> any).repeat.as(:box_label) >>
            line_end >>
            ws? >>
            statements.as(:box_statements) >>
            ws? >>
            str('end') >> line_end
        end

        # Control structures
        rule(:control_structure) do
          loop_structure |
            alt_structure |
            opt_structure |
            par_structure |
            critical_structure |
            break_structure
        end

        rule(:loop_structure) do
          str('loop') >> space? >>
            (line_end.absent? >> any).repeat.as(:loop_label) >>
            line_end >>
            ws? >>
            statements.as(:loop_statements) >>
            ws? >>
            str('end') >> line_end
        end

        rule(:alt_structure) do
          str('alt') >> space? >>
            (line_end.absent? >> any).repeat.as(:alt_label) >>
            line_end >>
            ws? >>
            statements.as(:alt_statements) >>
            ws? >>
            (
              str('else') >> space? >>
              (line_end.absent? >> any).repeat.as(:else_label) >>
              line_end >>
              ws? >>
              statements.as(:else_statements) >>
              ws?
            ).repeat.as(:else_blocks) >>
            str('end') >> line_end
        end

        rule(:opt_structure) do
          str('opt') >> space? >>
            (line_end.absent? >> any).repeat.as(:opt_label) >>
            line_end >>
            ws? >>
            statements.as(:opt_statements) >>
            ws? >>
            str('end') >> line_end
        end

        rule(:par_structure) do
          str('par') >> space? >>
            (line_end.absent? >> any).repeat.as(:par_label) >>
            line_end >>
            ws? >>
            statements.as(:par_statements) >>
            ws? >>
            (
              str('and') >> space? >>
              (line_end.absent? >> any).repeat.as(:and_label) >>
              line_end >>
              ws? >>
              statements.as(:and_statements) >>
              ws?
            ).repeat.as(:and_blocks) >>
            str('end') >> line_end
        end

        rule(:critical_structure) do
          str('critical') >> space? >>
            (line_end.absent? >> any).repeat.as(:critical_label) >>
            line_end >>
            ws? >>
            statements.as(:critical_statements) >>
            ws? >>
            (
              str('option') >> space? >>
              (line_end.absent? >> any).repeat.as(:option_label) >>
              line_end >>
              ws? >>
              statements.as(:option_statements) >>
              ws?
            ).repeat.as(:option_blocks) >>
            str('end') >> line_end
        end

        rule(:break_structure) do
          str('break') >> space? >>
            (line_end.absent? >> any).repeat.as(:break_label) >>
            line_end >>
            ws? >>
            statements.as(:break_statements) >>
            ws? >>
            str('end') >> line_end
        end

        # Label can be quoted or unquoted text
        rule(:label) do
          string | unquoted_label
        end

        rule(:unquoted_label) do
          (line_end.absent? >> any).repeat(1)
        end
      end
    end
  end
end