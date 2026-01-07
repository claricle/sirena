# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for State diagrams.
      #
      # Handles State diagram syntax including states, transitions,
      # composite states, special state markers (choice, fork, join),
      # and concurrent states.
      class StateDiagram < Common
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
          (str('stateDiagram-v2') | str('stateDiagram')).as(:header) >>
            ws? >>
            direction.maybe.as(:direction)
        end

        rule(:direction) do
          (str('TD') | str('TB') | str('LR') | str('RL')).as(:dir_value)
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          state_declaration |
            transition |
            note_statement |
            standalone_state
        end

        # State declaration with description, marker, or composite body
        rule(:state_declaration) do
          str('state').as(:keyword) >> space >>
            state_id.as(:state_id) >> space? >>
            (
              state_marker.as(:marker) |
              state_description.as(:description) |
              composite_body.as(:composite)
            ).maybe >>
            line_end
        end

        # Transition between states
        rule(:transition) do
          from_state.as(:from) >> space? >>
            arrow >>
            space? >>
            to_state.as(:to) >>
            transition_label.maybe.as(:label) >>
            (
              space? >> arrow >> space? >> to_state.as(:chain_to)
            ).repeat.as(:chain) >>
            line_end
        end

        # Note statement
        rule(:note_statement) do
          str('note').as(:note_keyword) >> space >>
            note_position.as(:position) >> space >>
            str('of') >> space >>
            state_id.as(:note_target) >> space? >>
            (colon >> space? >> note_text.as(:note_text)).maybe >>
            line_end
        end

        # Standalone state (just an identifier)
        rule(:standalone_state) do
          state_id.as(:state_id) >> line_end
        end

        # From state in transition
        rule(:from_state) do
          start_end_marker | state_id
        end

        # To state in transition
        rule(:to_state) do
          start_end_marker | state_id
        end

        # Start/end marker [*]
        rule(:start_end_marker) do
          lbracket >> asterisk >> rbracket
        end

        # State ID (identifier or quoted string)
        rule(:state_id) do
          string | identifier
        end

        # State description (after colon)
        rule(:state_description) do
          colon >> space? >>
            (line_end.absent? >> lbrace.absent? >> any).repeat(1)
        end

        # State marker: <<choice>>, <<fork>>, <<join>>
        rule(:state_marker) do
          str('<<') >>
            (str('choice') | str('fork') | str('join')).as(:marker_type) >>
            str('>>')
        end

        # Composite state body with nested statements
        rule(:composite_body) do
          lbrace >> ws? >>
            composite_statements.maybe >>
            ws? >> rbrace
        end

        # Statements within composite state
        rule(:composite_statements) do
          (composite_statement >> ws?).repeat(1)
        end

        rule(:composite_statement) do
          concurrent_separator |
            state_declaration |
            transition |
            note_statement |
            standalone_state
        end

        # Concurrent state separator
        rule(:concurrent_separator) do
          str('--').as(:concurrent_sep) >> line_end
        end

        # Arrow for transitions
        rule(:arrow) do
          str('-->').as(:arrow)
        end

        # Transition label (after colon)
        rule(:transition_label) do
          space? >> colon >> space? >>
            (line_end.absent? >> arrow.absent? >> any).repeat(1).as(:label_text)
        end

        # Note position
        rule(:note_position) do
          str('left') | str('right')
        end

        # Note text
        rule(:note_text) do
          (line_end.absent? >> any).repeat(1)
        end

        # Line terminators for State diagrams
        rule(:line_end) do
          semicolon.maybe >> space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end